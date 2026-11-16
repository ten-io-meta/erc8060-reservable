const { expect } = require("chai");
const { ethers } = require("hardhat");

const ETH = ethers.constants.AddressZero;
const BN = ethers.BigNumber.from;
function rng(seed) {
  let state = seed >>> 0;
  return (max) => {
    if (max <= 0) throw new Error("invalid random bound");
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state % max;
  };
}
async function mustRevert(promise, reason) {
  let failure;
  try { await promise; } catch (error) { failure = error; }
  expect(failure, "expected EVM revert").to.exist;
  if (reason) expect(failure.message).to.include(reason);
}
async function payoutDelta(recipient, sendTransaction, expectedWei) {
  const before = await ethers.provider.getBalance(recipient.address);
  const receipt = await (await sendTransaction()).wait();
  const gasCost = receipt.gasUsed.mul(receipt.effectiveGasPrice);
  const after = await ethers.provider.getBalance(recipient.address);
  expect(after.add(gasCost).sub(before).eq(BN(expectedWei))).to.equal(true);
}

describe("ETH coverage invariant models — deterministic stateful sequences", function () {
  let wallets, strict, conditional;
  beforeEach(async function () {
    wallets = await ethers.getSigners();
    strict = await (await ethers.getContractFactory("ERC8060NativeETHReference")).deploy();
    conditional = await (await ethers.getContractFactory("ReservableConditionalETHReference")).deploy();
    await strict.deployed();
    await conditional.deployed();
  });

  it("strict profile: 48 mint/transfer/burn/unauthorized steps preserve every ETH liability", async function () {
    const random = rng(20261116);
    const model = [];

    async function mintOne() {
      const who = random(3), amount = 5000 + random(100000);
      await strict.connect(wallets[who]).mint({ value: amount });
      model.push({ id: model.length + 1, owner: who, amount, live: true });
    }
    async function assertState(step) {
      const sum = model.filter(x => x.live).reduce((s, x) => s + x.amount, 0);
      expect((await strict.totalRedeemableValue()).eq(BN(sum)), "total liabilities at step " + step).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).eq(BN(sum)), "real contract ETH at step " + step).to.equal(true);
      expect(await strict.isSolvent()).to.equal(true);
      expect((await strict.nextTokenId()).toNumber()).to.equal(model.length + 1);
      for (const entry of model) {
        if (entry.live) {
          expect(await strict.ownerOf(entry.id)).to.equal(wallets[entry.owner].address);
          expect((await strict["valueOf(uint256)"](entry.id)).eq(BN(entry.amount))).to.equal(true);
        } else {
          await mustRevert(strict.ownerOf(entry.id));
          await mustRevert(strict["valueOf(uint256)"](entry.id), "nonexistent token");
        }
      }
    }

    await mintOne();
    await assertState("initial");
    for (let step = 0; step < 48; step++) {
      const live = model.filter(x => x.live);
      const op = step % 4;
      if (op === 0 && live.length < 4 || live.length === 0) {
        await mintOne();
      } else {
        const item = live[random(live.length)];
        if (op === 1 || (op === 0 && live.length >= 4)) {
          const next = (item.owner + 1 + random(2)) % 3;
          await strict.connect(wallets[item.owner]).transferFrom(
            wallets[item.owner].address, wallets[next].address, item.id
          );
          item.owner = next;
        } else if (op === 2) {
          await payoutDelta(wallets[item.owner], () =>
            strict.connect(wallets[item.owner]).burn(item.id), item.amount);
          item.live = false;
        } else {
          await mustRevert(
            strict.connect(wallets[(item.owner + 1) % 3]).burn(item.id),
            "not NFT owner"
          );
        }
      }
      await assertState(step);
    }
    for (const entry of model.filter(x => x.live)) {
      await payoutDelta(wallets[entry.owner], () =>
        strict.connect(wallets[entry.owner]).burn(entry.id), entry.amount);
      entry.live = false;
      await assertState("final " + entry.id);
    }
    expect((await ethers.provider.getBalance(strict.address)).isZero()).to.equal(true);
  });

  for (const seed of [8060, 20261116]) {
    it("conditional profile: 81-step per-NFT/per-spender ETH model, seed " + seed, async function () {
      const random = rng(seed);
      const owners = wallets.slice(0, 3);
      const spenders = wallets.slice(3, 5);
      const outsider = wallets[5];
      const model = [];

      async function mintOne() {
        const who = random(3), amount = 100000 + random(500000);
        await conditional.connect(owners[who]).mint({ value: amount });
        model.push({ id: model.length + 1, owner: who, amount,
          locked: [0, 0], approved: [0, 0], live: true });
        return model[model.length - 1];
      }
      async function assertState(step) {
        const sum = model.filter(x => x.live).reduce((s, x) => s + x.amount, 0);
        expect((await conditional.totalBacked()).eq(BN(sum)), "book liabilities step " + step).to.equal(true);
        expect((await ethers.provider.getBalance(conditional.address)).eq(BN(sum)), "contract ETH step " + step).to.equal(true);
        expect(await conditional.isSolvent()).to.equal(true);
        expect((await conditional.nextTokenId()).toNumber()).to.equal(model.length + 1);
        for (const x of model) {
          if (!x.live) {
            await mustRevert(conditional.ownerOf(x.id));
            await mustRevert(conditional.backingOf(x.id), "nonexistent token");
            continue;
          }
          const locked = x.locked[0] + x.locked[1];
          expect(locked <= x.amount, "no over-allocation for " + x.id).to.equal(true);
          expect(await conditional.ownerOf(x.id)).to.equal(owners[x.owner].address);
          expect((await conditional.backingOf(x.id)).eq(BN(x.amount))).to.equal(true);
          expect((await conditional.lockedValue(x.id, ETH)).eq(BN(locked))).to.equal(true);
          expect((await conditional.availableValue(x.id, ETH)).eq(BN(x.amount - locked))).to.equal(true);
          for (let i = 0; i < 2; i++) {
            const room = Math.max(0, x.approved[i] - x.locked[i]);
            expect((await conditional.reserveAllowance(x.id, spenders[i].address, ETH)).eq(BN(room))).to.equal(true);
          }
        }
      }

      await mintOne();
      await mintOne();
      await mintOne();
      // Guarantee at least one outstanding lock before the randomized sequence.
      let first = model[0];
      await conditional.connect(owners[first.owner]).approveReserve(first.id, spenders[0].address, ETH, 200000);
      first.approved[0] = 200000;
      await conditional.connect(spenders[0]).reserveValue(first.id, ETH, 125000);
      first.locked[0] = 125000;
      await assertState("initial");

      for (let step = 0; step < 81; step++) {
        const live = model.filter(x => x.live);
        const op = step % 9;
        let x = live.length > 0 ? live[random(live.length)] : await mintOne();
        const who = random(2);
        const current = owners[x.owner];
        const spender = spenders[who];
        const locked = x.locked[0] + x.locked[1];
        const available = x.amount - locked;
        const room = Math.max(0, x.approved[who] - x.locked[who]);

        if (op === 0) { // New ETH deposit to one NFT.
          const amount = 1000 + random(60000);
          await conditional.connect(current).deposit(x.id, { value: amount });
          x.amount += amount;
        } else if (op === 1) { // Grant/revoke; committed locks must not change.
          const approved = random(450000);
          await conditional.connect(current).approveReserve(x.id, spender.address, ETH, approved);
          x.approved[who] = approved;
        } else if (op === 2) { // Reserve, sometimes deliberately exceed room.
          const maxReserve = Math.min(room, available);
          if (maxReserve > 0) {
            const amount = 1 + random(maxReserve);
            await conditional.connect(spender).reserveValue(x.id, ETH, amount);
            x.locked[who] += amount;
          } else {
            await mustRevert(conditional.connect(spender).reserveValue(x.id, ETH, 1));
          }
        } else if (op === 3) { // Only the original spender may release.
          if (x.locked[who] > 0) {
            const amount = 1 + random(x.locked[who]);
            await conditional.connect(spender).releaseValue(x.id, ETH, amount);
            x.locked[who] -= amount;
          } else {
            await mustRevert(conditional.connect(spender).releaseValue(x.id, ETH, 1), "release exceeds allocation");
          }
        } else if (op === 4) { // Measure actual owner ETH payout after gas.
          if (available > 0) {
            const amount = 1 + random(available);
            await payoutDelta(current, () => conditional.connect(current).withdrawAvailable(x.id, amount), amount);
            x.amount -= amount;
          } else {
            await mustRevert(conditional.connect(current).withdrawAvailable(x.id, 1), "insufficient available");
          }
        } else if (op === 5) { // Transfer revokes unused approvals, but not locks.
          const next = (x.owner + 1 + random(2)) % 3;
          await conditional.connect(current).transferFrom(current.address, owners[next].address, x.id);
          x.owner = next;
          x.approved = [0, 0];
        } else if (op === 6) { // Unauthorized and overspending attempts.
          await mustRevert(conditional.connect(outsider).withdrawAvailable(x.id, 1), "not NFT owner");
          await mustRevert(conditional.connect(outsider).releaseValue(x.id, ETH, 1), "release exceeds allocation");
          await mustRevert(conditional.connect(spender).reserveValue(x.id, ETH, room + 1));
        } else if (op === 7) { // Add more independent NFT liabilities.
          if (live.length < 5) await mintOne();
          else {
            const approved = random(300000);
            await conditional.connect(current).approveReserve(x.id, spender.address, ETH, approved);
            x.approved[who] = approved;
          }
        } else if (op === 8) { // Locks block terminal redemption.
          if (locked !== 0) {
            await mustRevert(conditional.connect(current).redeemWhenUnlocked(x.id),
              "active reservation blocks redemption");
          } else {
            await payoutDelta(current, () =>
              conditional.connect(current).redeemWhenUnlocked(x.id), x.amount);
            x.live = false;
          }
        }
        await assertState(seed + ":" + step);
      }

      // End state: release all commitments, redeem every token, leave no ETH
      // liabilities and no asset balance stranded in the reference contract.
      for (const x of model.filter(x => x.live)) {
        for (let who = 0; who < 2; who++) {
          if (x.locked[who] > 0) {
            await conditional.connect(spenders[who]).releaseValue(x.id, ETH, x.locked[who]);
            x.locked[who] = 0;
          }
        }
        await payoutDelta(owners[x.owner], () =>
          conditional.connect(owners[x.owner]).redeemWhenUnlocked(x.id), x.amount);
        x.live = false;
        await assertState(seed + ":close-" + x.id);
      }
      expect((await conditional.totalBacked()).isZero()).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
    });
  }

  it("rejecting ETH receiver cannot withdraw or redeem; state and ETH are atomically unchanged", async function () {
    const probe = await (await ethers.getContractFactory("RejectETHReceiverProbe")).deploy();
    await probe.deployed();
    const initial = BN(100000);
    await probe.mintConditionalInto(conditional.address, { value: initial });
    const before = await ethers.provider.getBalance(conditional.address);
    await mustRevert(probe.attemptConditionalWithdraw(conditional.address, 1, 20000), "ETH withdrawal failed");
    expect(await conditional.ownerOf(1)).to.equal(probe.address);
    expect((await conditional.backingOf(1)).eq(initial)).to.equal(true);
    expect((await conditional.totalBacked()).eq(initial)).to.equal(true);
    expect((await ethers.provider.getBalance(conditional.address)).eq(before)).to.equal(true);
    await mustRevert(probe.attemptConditionalRedeem(conditional.address, 1), "ETH redemption failed");
    expect(await conditional.ownerOf(1)).to.equal(probe.address);
    expect((await conditional.backingOf(1)).eq(initial)).to.equal(true);
    expect((await conditional.totalBacked()).eq(initial)).to.equal(true);
    expect((await ethers.provider.getBalance(conditional.address)).eq(before)).to.equal(true);
  });

  it("forced surplus ETH cannot inflate NFT claims or be extracted by a redeeming owner", async function () {
    const deposit = BN(20000), extra = BN(5000);
    await strict.mint({ value: deposit });
    await conditional.mint({ value: deposit });
    const Force = await ethers.getContractFactory("ForceETHSurplusProbe");
    const giftStrict = await Force.deploy({ value: extra });
    const giftConditional = await Force.deploy({ value: extra });
    await giftStrict.deployed();
    await giftConditional.deployed();
    await giftStrict.sendSurplus(strict.address);
    await giftConditional.sendSurplus(conditional.address);

    expect((await strict["valueOf(uint256)"](1)).eq(deposit)).to.equal(true);
    expect((await strict.totalRedeemableValue()).eq(deposit)).to.equal(true);
    expect((await conditional.backingOf(1)).eq(deposit)).to.equal(true);
    expect((await conditional.totalBacked()).eq(deposit)).to.equal(true);
    expect((await ethers.provider.getBalance(strict.address)).eq(deposit.add(extra))).to.equal(true);
    expect((await ethers.provider.getBalance(conditional.address)).eq(deposit.add(extra))).to.equal(true);
    expect(await strict.isSolvent()).to.equal(true);
    expect(await conditional.isSolvent()).to.equal(true);

    await payoutDelta(wallets[0], () => strict.burn(1), deposit);
    await payoutDelta(wallets[0], () => conditional.redeemWhenUnlocked(1), deposit);
    expect((await ethers.provider.getBalance(strict.address)).eq(extra)).to.equal(true);
    expect((await ethers.provider.getBalance(conditional.address)).eq(extra)).to.equal(true);
    expect((await strict.totalRedeemableValue()).isZero()).to.equal(true);
    expect((await conditional.totalBacked()).isZero()).to.equal(true);
  });
});
