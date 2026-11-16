const { expect } = require("chai");
const { ethers } = require("hardhat");

// Reproducible state-machine fuzzing. A seed printed in the test title lets
// anyone rerun the exact sequence when a property fails. No Mainnet RPC.
const ETH = ethers.constants.AddressZero;
const BAD_ASSET = "0x0000000000000000000000000000000000000001";
const BN = ethers.BigNumber.from;
const SEEDS = [1, 7, 8060, 8098, 1337, 20261116, 0xdeadbeef, 0xffffffff];

function rng(seed) {
  let state = seed >>> 0 || 1;
  return (n) => {
    if (n <= 0) throw new Error("invalid rng range " + n);
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) % n;
  };
}
async function revert(promise, reason) {
  let caught;
  try { await promise; } catch (err) { caught = err; }
  expect(caught, "expected revert").to.exist;
  if (reason) expect(caught.message).to.include(reason);
}
function equals(actual, amount, label) {
  expect(actual.eq(BN(amount)), label).to.equal(true);
}
async function netReceived(signer, fn, expected) {
  const before = await ethers.provider.getBalance(signer.address);
  const receipt = await (await fn()).wait();
  const fee = receipt.gasUsed.mul(receipt.effectiveGasPrice);
  const after = await ethers.provider.getBalance(signer.address);
  equals(after.add(fee).sub(before), expected, "exact ETH payout");
}

describe("Break the combined reference — seeded adversarial state machines", function () {
  let owners, spenders, outsider, strict, reserved;
  beforeEach(async function () {
    const wallets = await ethers.getSigners();
    owners = wallets.slice(0, 3);
    spenders = wallets.slice(3, 6);
    outsider = wallets[6];
    strict = await (await ethers.getContractFactory("ERC8060NativeETHReference")).deploy();
    reserved = await (await ethers.getContractFactory("ReservableConditionalETHReference")).deploy();
    await strict.deployed();
    await reserved.deployed();
  });

  for (const seed of SEEDS) {
    it("conditional: 140 adversarial transitions / seed=" + seed, async function () {
      this.timeout(240000);
      const random = rng(seed);
      const model = [];
      async function mintOne() {
        const owner = random(3);
        const amount = 50000 + random(300000);
        await reserved.connect(owners[owner]).mint({ value: amount });
        const token = {
          id: model.length + 1, owner, amount, live: true, epoch: 0,
          reservations: spenders.map(() => ({ approved: 0, locked: 0, epoch: 0 }))
        };
        model.push(token);
        return token;
      }
      function totalLocked(t) {
        return t.reservations.reduce((sum, r) => sum + r.locked, 0);
      }
      function allowance(t, index) {
        const r = t.reservations[index];
        return t.epoch === r.epoch ? Math.max(0, r.approved - r.locked) : 0;
      }
      async function check(step, touched) {
        const live = model.filter(x => x.live);
        const sum = live.reduce((a, x) => a + x.amount, 0);
        equals(await reserved.totalBacked(), sum, "aggregate owed at " + step);
        equals(await ethers.provider.getBalance(reserved.address), sum, "actual ETH at " + step);
        expect(await reserved.isSolvent(), "solvent " + step).to.equal(true);
        equals(await reserved.nextTokenId(), model.length + 1, "monotonic ID");
        const checking = (step % 7 === 0) ? live : (touched && touched.live ? [touched] : []);
        for (const t of checking) {
          const locked = totalLocked(t);
          expect(locked <= t.amount, "over-reservation at step " + step + " token " + t.id).to.equal(true);
          expect(await reserved.ownerOf(t.id)).to.equal(owners[t.owner].address);
          equals(await reserved.backingOf(t.id), t.amount, "per-token owed");
          equals(await reserved.lockedValue(t.id, ETH), locked, "per-token locked");
          equals(await reserved.availableValue(t.id, ETH), t.amount - locked, "available = owed - locked");
          for (let i = 0; i < spenders.length; i++) {
            equals(await reserved.reserveAllowance(t.id, spenders[i].address, ETH),
              allowance(t, i), "epoch/allowance spender " + i);
          }
        }
      }

      await mintOne();
      await mintOne();
      await check("start", model[0]);

      for (let step = 0; step < 140; step++) {
        let active = model.filter(t => t.live);
        if (active.length === 0) {
          await mintOne();
          active = model.filter(t => t.live);
        }
        const t = active[random(active.length)];
        const op = random(14);
        const who = random(3);
        const current = owners[t.owner], spender = spenders[who];
        const r = t.reservations[who];
        const available = t.amount - totalLocked(t);
        const room = allowance(t, who);

        if (op === 0) { // mint more liabilities or deposit into an existing NFT
          if (active.length < 5) await mintOne();
          else {
            const amount = 1 + random(150000);
            await reserved.connect(current).deposit(t.id, { value: amount });
            t.amount += amount;
          }
        } else if (op === 1) { // deposit exact ETH
          const amount = 1 + random(150000);
          await reserved.connect(current).deposit(t.id, { value: amount });
          t.amount += amount;
        } else if (op === 2) { // revoke / reapprove even below already-locked amount
          const amount = random(450000);
          await reserved.connect(current).approveReserve(t.id, spender.address, ETH, amount);
          r.approved = amount;
          r.epoch = t.epoch;
        } else if (op === 3) { // reserve up to BOTH allowance and available balance
          const max = Math.min(room, available);
          if (max > 0) {
            const amount = 1 + random(max);
            await reserved.connect(spender).reserveValue(t.id, ETH, amount);
            r.locked += amount;
          } else {
            await revert(reserved.connect(spender).reserveValue(t.id, ETH, 1));
          }
        } else if (op === 4) { // release persists after transfer and revocation
          if (r.locked > 0) {
            const amount = 1 + random(r.locked);
            await reserved.connect(spender).releaseValue(t.id, ETH, amount);
            r.locked -= amount;
          } else {
            await revert(reserved.connect(spender).releaseValue(t.id, ETH, 1), "release exceeds allocation");
          }
        } else if (op === 5) { // owner withdraws some or all unreserved ETH
          if (available > 0) {
            const amount = random(3) === 0 ? available : 1 + random(available);
            await netReceived(current, () => reserved.connect(current).withdrawAvailable(t.id, amount), amount);
            t.amount -= amount;
          } else {
            await revert(reserved.connect(current).withdrawAvailable(t.id, 1), "insufficient available");
          }
        } else if (op === 6 || op === 7) { // direct transfer OR approved operator transfer
          const next = (t.owner + 1 + random(2)) % 3;
          if (op === 7) {
            await reserved.connect(current).approve(spender.address, t.id);
            await reserved.connect(spender).transferFrom(current.address, owners[next].address, t.id);
          } else {
            await reserved.connect(current).transferFrom(current.address, owners[next].address, t.id);
          }
          t.owner = next;
          t.epoch++; // old grants invalidate, active locks do not
        } else if (op === 8) { // deliberately exceed one binding limit
          await revert(reserved.connect(spender).reserveValue(t.id, ETH, Math.min(room, available) + 1));
        } else if (op === 9) { // locked tokens must not be destroyed, unlocked tokens redeem fully
          if (totalLocked(t) > 0) {
            await revert(reserved.connect(current).redeemWhenUnlocked(t.id),
              "active reservation blocks redemption");
          } else {
            await netReceived(current, () => reserved.connect(current).redeemWhenUnlocked(t.id), t.amount);
            t.live = false;
            await revert(reserved.ownerOf(t.id));
          }
        } else if (op === 10) { // self transfer should not revoke approvals
          await reserved.connect(current).transferFrom(current.address, current.address, t.id);
        } else if (op === 11) { // unrelated actor cannot reserve, unlock or remove backing
          await revert(reserved.connect(outsider).approveReserve(t.id, spender.address, ETH, 1),
            "not NFT owner");
          await revert(reserved.connect(outsider).releaseValue(t.id, ETH, 1),
            "release exceeds allocation");
          await revert(reserved.connect(outsider).withdrawAvailable(t.id, 1),
            "not NFT owner");
        } else if (op === 12) { // invalid asset and zero address spender
          await revert(reserved.connect(current).approveReserve(t.id, spender.address, BAD_ASSET, 1), "ETH only");
          await revert(reserved.connect(current).approveReserve(t.id, ETH, ETH, 1), "invalid spender");
          await revert(reserved.connect(spender).reserveValue(t.id, BAD_ASSET, 1), "ETH only");
        } else { // try releasing more than the caller personally locked
          await revert(reserved.connect(spender).releaseValue(t.id, ETH, r.locked + 1),
            "release exceeds allocation");
        }
        await check(seed + ":" + step + ":op" + op, t);
      }

      // A cooperative spender can release all locks; then every owner can
      // reclaim exact remaining backing, leaving zero ETH stuck.
      for (const t of model.filter(x => x.live)) {
        for (let i = 0; i < spenders.length; i++) {
          if (t.reservations[i].locked > 0) {
            await reserved.connect(spenders[i]).releaseValue(t.id, ETH, t.reservations[i].locked);
            t.reservations[i].locked = 0;
          }
        }
        await netReceived(owners[t.owner],
          () => reserved.connect(owners[t.owner]).redeemWhenUnlocked(t.id), t.amount);
        t.live = false;
        await check(seed + ":final-" + t.id, t);
      }
      equals(await ethers.provider.getBalance(reserved.address), 0, "no stranded ETH");
    });
  }

  for (const seed of [8060, 20261116, 0xdeadbeef, 999]) {
    it("strict: 90 adversarial mint/transfer/redeem steps / seed=" + seed, async function () {
      this.timeout(180000);
      const random = rng(seed);
      const model = [];
      async function mintOne() {
        const who = random(3), amount = 1 + random(300000);
        await strict.connect(owners[who]).mint({ value: amount });
        model.push({ id: model.length + 1, owner: who, amount, live: true });
      }
      async function check(step) {
        const active = model.filter(t => t.live);
        const total = active.reduce((a, x) => a + x.amount, 0);
        equals(await strict.totalRedeemableValue(), total, "liabilities at " + step);
        equals(await ethers.provider.getBalance(strict.address), total, "contract ETH at " + step);
        expect(await strict.isSolvent()).to.equal(true);
        equals(await strict.nextTokenId(), model.length + 1);
        if (step % 8 === 0) for (const t of active) {
          expect(await strict.ownerOf(t.id)).to.equal(owners[t.owner].address);
          equals(await strict["valueOf(uint256)"](t.id), t.amount);
        }
      }
      await mintOne();
      for (let step = 0; step < 90; step++) {
        const live = model.filter(t => t.live);
        const op = random(7);
        if (op === 0 || live.length === 0) {
          await mintOne();
        } else {
          const t = live[random(live.length)], current = owners[t.owner];
          if (op === 1 || op === 2) {
            const next = (t.owner + 1 + random(2)) % 3;
            await strict.connect(current).transferFrom(current.address, owners[next].address, t.id);
            t.owner = next;
          } else if (op === 3) {
            await netReceived(current, () => strict.connect(current).burn(t.id), t.amount);
            t.live = false;
          } else if (op === 4) {
            await revert(strict.connect(outsider).burn(t.id), "not NFT owner");
          } else if (op === 5) {
            await strict.connect(current).approve(spenders[0].address, t.id);
            await revert(strict.connect(spenders[0]).burn(t.id), "not NFT owner");
          } else {
            await strict.connect(current).transferFrom(current.address, current.address, t.id);
          }
        }
        await check(step);
      }
      for (const t of model.filter(x => x.live)) {
        await netReceived(owners[t.owner], () => strict.connect(owners[t.owner]).burn(t.id), t.amount);
        t.live = false;
      }
      equals(await strict.totalRedeemableValue(), 0);
      equals(await ethers.provider.getBalance(strict.address), 0);
    });
  }

  it("ERC721 mint callbacks and ETH payout callbacks cannot redeem recursively (strict and conditional)", async function () {
    const Probe = await ethers.getContractFactory("ETHReentrancyProbe");
    for (const [target, conditional] of [[strict, false], [reserved, true]]) {
      const probe = await Probe.deploy();
      await probe.deployed();
      await probe.mintInto(target.address, conditional, { value: 23000 });
      await probe.mintInto(target.address, conditional, { value: 17000 });
      expect(await probe.mintReentryBlocked(), "reentrant mint callback must revert").to.equal(true);
      equals(await ethers.provider.getBalance(target.address), 40000);
      await probe.redeem(1, 2);
      expect(await probe.paymentReentryBlocked(), "reentrant ETH callback must revert").to.equal(true);
      expect(await target.ownerOf(2)).to.equal(probe.address);
      equals(await ethers.provider.getBalance(target.address), 17000);
      await probe.redeem(2, 0);
      equals(await ethers.provider.getBalance(target.address), 0);
      expect(await target.isSolvent()).to.equal(true);
    }
  });

  it("MaxUint256 approval is not permission to reserve more ETH than exists", async function () {
    await reserved.mint({ value: 5000 });
    await reserved.approveReserve(1, spenders[0].address, ETH, ethers.constants.MaxUint256);
    await revert(reserved.connect(spenders[0]).reserveValue(1, ETH, 5001), "insufficient available");
    await reserved.connect(spenders[0]).reserveValue(1, ETH, 5000);
    equals(await reserved.lockedValue(1, ETH), 5000);
    equals(await reserved.availableValue(1, ETH), 0);
    await revert(reserved.withdrawAvailable(1, 1), "insufficient available");
    await revert(reserved.redeemWhenUnlocked(1), "active reservation blocks redemption");
    await reserved.connect(spenders[0]).releaseValue(1, ETH, 5000);
    await reserved.redeemWhenUnlocked(1);
    equals(await ethers.provider.getBalance(reserved.address), 0);
  });

  it("a lost/uncooperative reserving spender can leave ETH locked indefinitely (design/liveness risk)", async function () {
    await reserved.mint({ value: 25000 });
    await reserved.approveReserve(1, spenders[0].address, ETH, 25000);
    await reserved.connect(spenders[0]).reserveValue(1, ETH, 25000);
    await reserved.transferFrom(owners[0].address, owners[1].address, 1);
    await reserved.connect(owners[1]).approveReserve(1, spenders[0].address, ETH, 0);
    await revert(reserved.connect(owners[1]).redeemWhenUnlocked(1),
      "active reservation blocks redemption");
    await revert(reserved.connect(owners[1]).withdrawAvailable(1, 1),
      "insufficient available");
    await revert(reserved.connect(owners[1]).releaseValue(1, ETH, 25000),
      "release exceeds allocation");
    equals(await reserved.totalBacked(), 25000);
    equals(await ethers.provider.getBalance(reserved.address), 25000);
    // No emergency owner-override exists: only the original spender can release.
  });
});
