const { expect } = require("chai");
const { ethers, network } = require("hardhat");

// Adversarial checks for properties that were not covered by the earlier 137-test suite.
describe("Reservable — invariant audit", function () {
  const ETH = ethers.constants.AddressZero;
  const ASSET_B = "0x0000000000000000000000000000000000000001";
  const TOKEN = 1;
  const OTHER = 2;
  const assets = [ETH, ASSET_B];

  let owner, newOwner, a, b, stranger, mock;

  async function mustRevert(promise, reason) {
    let e;
    try { await promise; } catch (err) { e = err; }
    expect(e, "expected revert").to.exist;
    if (reason) expect(e.message).to.include(reason);
  }

  beforeEach(async function () {
    [owner, newOwner, a, b, stranger] = await ethers.getSigners();
    const M = await ethers.getContractFactory("ERC8060ReservableMock");
    mock = await M.deploy();
    await mock.deployed();
    await mock.mintValue(TOKEN, ETH, 1000);
    await mock.mintValue(TOKEN, ASSET_B, 2000);
    await mock.mintToken(OTHER, owner.address);
    await mock.mintValue(OTHER, ETH, 3000);
    await mock.mintValue(OTHER, ASSET_B, 4000);
  });

  it("cannot mint token to zero or let a stranger mint a token", async function () {
    await mustRevert(mock.mintToken(3, ETH), "zero recipient");
    await mustRevert(mock.connect(stranger).mintToken(3, stranger.address), "not lab minter");
    expect(await mock.ownerOf(3)).to.equal(ETH);
  });

  it("cannot transfer token with or without locks to zero; state stays intact", async function () {
    await mock.approveReserve(TOKEN, a.address, ETH, 700);
    await mustRevert(mock.transferFrom(owner.address, ETH, TOKEN), "zero recipient");
    expect(await mock.ownerOf(TOKEN)).to.equal(owner.address);
    expect((await mock.reserveAllowance(TOKEN, a.address, ETH)).toNumber()).to.equal(700);
    await mock.connect(a).reserveValue(TOKEN, ETH, 300);
    await mustRevert(mock.transferFrom(owner.address, ETH, TOKEN), "zero recipient");
    expect(await mock.ownerOf(TOKEN)).to.equal(owner.address);
    expect((await mock.lockedValue(TOKEN, ETH)).toNumber()).to.equal(300);
    expect((await mock.reserveAllowance(TOKEN, a.address, ETH)).toNumber()).to.equal(400);
  });

  it("honors per-spender locks when permissions are revoked and owner changes", async function () {
    await mock.approveReserve(TOKEN, a.address, ETH, 600);
    await mock.approveReserve(TOKEN, b.address, ETH, 600);
    await mock.connect(a).reserveValue(TOKEN, ETH, 400);
    await mock.connect(b).reserveValue(TOKEN, ETH, 300);
    await mock.approveReserve(TOKEN, a.address, ETH, 0);
    await mock.transferFrom(owner.address, newOwner.address, TOKEN);
    expect((await mock.lockedValue(TOKEN, ETH)).toNumber()).to.equal(700);
    expect((await mock.availableValue(TOKEN, ETH)).toNumber()).to.equal(300);
    expect((await mock.reserveAllowance(TOKEN, b.address, ETH)).isZero()).to.equal(true);
    await mustRevert(mock.connect(b).reserveValue(TOKEN, ETH, 1), "exceeds reserve allowance");
    await mustRevert(mock.connect(newOwner).withdraw(TOKEN, ETH, 301), "insufficient available value");
    await mustRevert(mock.connect(stranger).releaseValue(TOKEN, ETH, 1), "release exceeds locked");
    await mock.connect(a).releaseValue(TOKEN, ETH, 400);
    await mock.connect(b).releaseValue(TOKEN, ETH, 300);
    expect((await mock.lockedValue(TOKEN, ETH)).isZero()).to.equal(true);
    expect((await mock.availableValue(TOKEN, ETH)).toNumber()).to.equal(1000);
  });

  it("preserves exact accounting through 64 deterministic multi-asset/multi-token operations", async function () {
    const tokens = [TOKEN, OTHER];
    const spenders = [a, b];
    const model = {};
    const key = (t,asset) => t + ":" + asset;
    for (const t of tokens) for (const asset of assets) {
      model[key(t, asset)] = { total: (await mock.totalValue(t,asset)).toNumber(), locked: [0,0], approvals: [0,0] };
    }
    // Fixed arithmetic sequence, reproducible in CI.
    for (let i = 0; i < 64; i++) {
      const t = tokens[i % 2], asset = assets[Math.floor(i / 2) % 2], who = i % 4 < 2 ? 0 : 1;
      const item = model[key(t, asset)], actor = spenders[who];
      if (i % 8 === 0) {
        const approval = 250 + (i % 5) * 30;
        await mock.approveReserve(t,actor.address,asset,approval);
        item.approvals[who] = approval;
      } else if (i % 3 === 0 && item.locked[who] > 0) {
        const amount = Math.min(item.locked[who], 17);
        await mock.connect(actor).releaseValue(t,asset,amount);
        item.locked[who] -= amount;
      } else {
        const outstanding = item.locked.reduce((x,y)=>x+y,0);
        const room = Math.max(0,item.approvals[who]-item.locked[who]);
        const amount = Math.min(23, room, item.total-outstanding);
        if (amount > 0) {
          await mock.connect(actor).reserveValue(t,asset,amount);
          item.locked[who] += amount;
        } else {
          await mustRevert(mock.connect(actor).reserveValue(t,asset,23));
        }
      }
      for (const token of tokens) for (const currentAsset of assets) {
        const expected = model[key(token,currentAsset)];
        const sum = expected.locked.reduce((x,y)=>x+y,0);
        expect((await mock.totalValue(token,currentAsset)).toNumber()).to.equal(expected.total);
        expect((await mock.lockedValue(token,currentAsset)).toNumber()).to.equal(sum);
        expect((await mock.availableValue(token,currentAsset)).toNumber()).to.equal(expected.total-sum);
        for (let k=0;k<spenders.length;k++){
          expect((await mock.reserveAllowance(token,spenders[k].address,currentAsset)).toNumber())
            .to.equal(Math.max(0,expected.approvals[k]-expected.locked[k]));
        }
      }
    }
  });

  it("a timed demo cannot claim payment and can refund after expiry", async function () {
    const Timed = await ethers.getContractFactory("TimedReservableEscrow");
    const timed = await Timed.deploy(mock.address);
    await timed.deployed();
    await mock.approveReserve(TOKEN, timed.address, ETH, 400);
    await mustRevert(
      timed.connect(stranger).createTimedEscrow(TOKEN,ETH,100,stranger.address,30),
      "not NFT owner"
    );
    await timed.createTimedEscrow(TOKEN,ETH,100,owner.address,30);
    await mustRevert(timed.settleTimedEscrow(0), "settlement not implemented");
    expect((await mock.lockedValue(TOKEN,ETH)).toNumber()).to.equal(100);
    await mustRevert(timed.refundExpiredEscrow(0), "deadline not reached");
    await network.provider.send("evm_increaseTime",[31]);
    await network.provider.send("evm_mine");
    await timed.connect(stranger).refundExpiredEscrow(0);
    expect((await mock.lockedValue(TOKEN,ETH)).isZero()).to.equal(true);
    expect((await mock.availableValue(TOKEN,ETH)).toNumber()).to.equal(1000);
    await mustRevert(timed.connect(stranger).refundExpiredEscrow(0),"escrow not active");
  });
});
