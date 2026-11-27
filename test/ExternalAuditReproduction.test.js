const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * These tests first reproduced the 5 unsafe pre-hardening behaviors on the
 * archived PR #19 main baseline. On this branch they assert those same
 * behaviors are rejected. Passing is NOT a funded financial protocol audit.
 */
describe("Reservable toy examples — post-remediation negative regressions", function () {
  const asset = ethers.constants.AddressZero;
  let issuer, previousSpender, newOwner, outsider, mock;
  async function expectRevert(call, message) {
    try {
      const tx = await call;
      if (tx?.wait) await tx.wait();
      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include(message);
    }
  }
  beforeEach(async function () {
    [issuer, previousSpender, newOwner, outsider] = await ethers.getSigners();
    mock = await (await ethers.getContractFactory("ERC8060ReservableMock")).deploy();
    await mock.deployed();
    await mock.mintValue(1, asset, 1000);
  });
  it("FIX CHECK R-01: transfer invalidates unused permissions; active locks remain independently releasable", async function () {
    await mock.approveReserve(1, previousSpender.address, asset, 200);
    await mock.connect(previousSpender).reserveValue(1, asset, 40);
    await mock.transferFrom(issuer.address, newOwner.address, 1);
    expect((await mock.reserveAllowance(1, previousSpender.address, asset)).eq(0)).to.equal(true);
    expect((await mock.lockedValue(1, asset)).eq(40)).to.equal(true);
    await expectRevert(mock.connect(previousSpender).reserveValue(1, asset, 1), "exceeds reserve allowance");
    await mock.connect(previousSpender).releaseValue(1, asset, 40);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
    await mock.connect(newOwner).approveReserve(1, previousSpender.address, asset, 25);
    expect((await mock.reserveAllowance(1, previousSpender.address, asset)).eq(25)).to.equal(true);
    await mock.connect(previousSpender).reserveValue(1, asset, 25);
    expect((await mock.lockedValue(1, asset)).eq(25)).to.equal(true);
  });
  it("FIX CHECK R-02: unrelated actors cannot create bookkeeping token identities", async function () {
    await expectRevert(mock.connect(outsider).mintToken(2, previousSpender.address), "not mock issuer");
    await expectRevert(mock.mintToken(2, ethers.constants.AddressZero), "invalid recipient");
    await mock.mintToken(2, previousSpender.address);
    expect(await mock.ownerOf(2)).to.equal(previousSpender.address);
    expect((await mock.totalValue(2, asset)).eq(0)).to.equal(true);
  });
  it("FIX CHECK R-03: bogus escrow settlement fails closed, even for the creator", async function () {
    const escrow = await (await ethers.getContractFactory("MinimalReservableEscrow")).deploy(mock.address);
    await escrow.deployed();
    await mock.approveReserve(1, escrow.address, asset, 200);
    await escrow.createEscrow(1, asset, 200, previousSpender.address);
    await expectRevert(escrow.connect(outsider).settleEscrow(0), "escrow payout not implemented");
    await expectRevert(escrow.settleEscrow(0), "escrow payout not implemented");
    const e = await escrow.escrows(0);
    expect(e.settled).to.equal(false);
    expect(e.active).to.equal(true);
    expect((await mock.lockedValue(1, asset)).eq(200)).to.equal(true);
    expect((await ethers.provider.getBalance(escrow.address)).eq(0)).to.equal(true);
  });
  it("FIX CHECK R-04: unrelated callers cannot release someone else's escrow lock", async function () {
    const escrow = await (await ethers.getContractFactory("MinimalReservableEscrow")).deploy(mock.address);
    await escrow.deployed();
    await mock.approveReserve(1, escrow.address, asset, 300);
    await escrow.createEscrow(1, asset, 300, previousSpender.address);
    await expectRevert(escrow.connect(outsider).releaseEscrow(0), "not escrow creator");
    expect((await mock.lockedValue(1, asset)).eq(300)).to.equal(true);
    await escrow.releaseEscrow(0);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
  });
  it("FIX CHECK R-05: unrelated caller cannot close another borrower's bookkeeping lock", async function () {
    const lending = await (await ethers.getContractFactory("MinimalLendingCollateral")).deploy(mock.address);
    await lending.deployed();
    await mock.approveReserve(1, lending.address, asset, 400);
    await lending.connect(previousSpender).openLoan(1, asset, 400);
    await expectRevert(lending.connect(outsider).closeLoan(0), "not loan borrower");
    expect((await mock.lockedValue(1, asset)).eq(400)).to.equal(true);
    // This is NOT real lender-authorized repayment: the toy model lacks a lender.
    await lending.connect(previousSpender).closeLoan(0);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
  });
  it("ADDITIONAL: unrelated actor cannot release task bond; pretend bond settlement is disabled", async function () {
    const b = await (await ethers.getContractFactory("AgentTaskBond")).deploy(mock.address);
    await b.deployed();
    await mock.approveReserve(1, b.address, asset, 100);
    await b.createTaskBond(1, asset, 100, previousSpender.address, ethers.utils.id("task"));
    await expectRevert(b.connect(outsider).releaseTaskBond(0), "not bond creator");
    await expectRevert(b.settleTaskBond(0), "bond payout not implemented");
    expect((await mock.lockedValue(1, asset)).eq(100)).to.equal(true);
    await b.releaseTaskBond(0);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
  });
  it("ADDITIONAL: timed escrow cannot simulate payment by setting settled flag", async function () {
    const t = await (await ethers.getContractFactory("TimedReservableEscrow")).deploy(mock.address);
    await t.deployed();
    await mock.approveReserve(1, t.address, asset, 100);
    await t.createTimedEscrow(1, asset, 100, previousSpender.address, 3600);
    await expectRevert(t.settleTimedEscrow(0), "timed escrow payout not implemented");
    expect((await mock.lockedValue(1, asset)).eq(100)).to.equal(true);
  });
});
