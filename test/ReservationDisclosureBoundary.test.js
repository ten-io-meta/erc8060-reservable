const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * These tests exercise only the source repository's bookkeeping-only mock.
 * They DO NOT reproduce native ETH payout or certify real ERC-8060 support.
 */
describe("Reservable disclosure vs strict ERC-8060 — negative capability controls", function () {
  const TOKEN_ID = 1;
  const NATIVE_ETH_ASSET_SENTINEL = ethers.constants.AddressZero;
  const wei = ethers.utils.parseEther;
  let mock, owner, reserver, recipient;

  beforeEach(async function () {
    [owner, reserver, recipient] = await ethers.getSigners();
    mock = await (await ethers.getContractFactory("ERC8060ReservableMock")).deploy();
    await mock.deployed();
  });

  async function expectRevert(call) {
    let didRevert = false;
    try {
      const tx = await call;
      if (tx?.wait) await tx.wait();
    } catch (_) {
      didRevert = true;
    }
    expect(didRevert).to.equal(true);
  }

  it("1 ETH recorded and 0.01 ETH reserved leaves 0.99 ETH available ONLY in bookkeeping", async function () {
    await mock.mintValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("1"));
    await mock.approveReserve(TOKEN_ID, reserver.address, NATIVE_ETH_ASSET_SENTINEL, wei("0.01"));
    await mock.connect(reserver).reserveValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("0.01"));

    expect((await mock.totalValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("1"))).to.equal(true);
    expect((await mock.lockedValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("0.01"))).to.equal(true);
    expect((await mock.availableValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("0.99"))).to.equal(true);
    await expectRevert(mock.withdraw(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("1")));

    // Mock 'mintValue' does NOT deposit real ETH; this is a key
    // counterexample to equating recorded amount and real collateral.
    expect((await ethers.provider.getBalance(mock.address)).eq(0)).to.equal(true);
    expect(Object.keys(mock.interface.functions).includes("burn(uint256)")).to.equal(false);
    expect(Object.keys(mock.interface.functions).includes("valueOf(uint256)")).to.equal(false);
  });

  it("unused permission is not an active economic reservation", async function () {
    await mock.mintValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("1"));
    await mock.approveReserve(TOKEN_ID, reserver.address, NATIVE_ETH_ASSET_SENTINEL, wei("0.7"));
    expect((await mock.reserveAllowance(TOKEN_ID, reserver.address, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("0.7"))).to.equal(true);
    expect((await mock.lockedValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(0)).to.equal(true);
    expect((await mock.availableValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("1"))).to.equal(true);
  });

  it("the bookkeeping mock does not implement ERC-165 or strict ERC-8060 discovery", async function () {
    const methods = Object.keys(mock.interface.functions);
    expect(methods.includes("supportsInterface(bytes4)")).to.equal(false);
    expect(methods.includes("valueOf(uint256)")).to.equal(false);
    expect(methods.includes("burn(uint256)")).to.equal(false);

    // An off-chain indexed event log, matching function names or a native
    // asset sentinel is not a self-authenticating ERC-165 profile claim.
    await expectRevert(
      owner.sendTransaction({ to: mock.address, data: "0x01ffc9a7", gasLimit: 100000 })
    );
  });

  it("recorded locks remain attached to token ID upon transfer; do not assume payout", async function () {
    await mock.mintValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("1"));
    await mock.approveReserve(TOKEN_ID, reserver.address, NATIVE_ETH_ASSET_SENTINEL, wei("0.01"));
    await mock.connect(reserver).reserveValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("0.01"));
    await mock.transferFrom(owner.address, recipient.address, TOKEN_ID);

    expect(await mock.ownerOf(TOKEN_ID)).to.equal(recipient.address);
    expect((await mock.lockedValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("0.01"))).to.equal(true);
    expect((await mock.availableValue(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL)).eq(wei("0.99"))).to.equal(true);
    await expectRevert(mock.connect(recipient).withdraw(TOKEN_ID, NATIVE_ETH_ASSET_SENTINEL, wei("1")));
    expect((await ethers.provider.getBalance(mock.address)).eq(0)).to.equal(true);
  });
});
