const { expect } = require("chai");
const { ethers } = require("hardhat");

// Security regression tests for the hardened ACCOUNTING-ONLY demonstrations.
// All three settlement/payout paths remain unimplemented by design.
describe("Reservable - demo security regression", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const AMOUNT = ethers.utils.parseEther("0.3");
  let owner, stranger, nft, escrow;

  beforeEach(async function () {
    [owner, stranger] = await ethers.getSigners();
    nft = await (await ethers.getContractFactory("ERC8060ReservableMock")).deploy();
    await nft.deployed();
    await nft.mintValue(ID, ETH, ethers.utils.parseEther("1"));
    escrow = await (await ethers.getContractFactory("MinimalReservableEscrow")).deploy(nft.address);
    await escrow.deployed();
    await nft.approveReserve(ID, escrow.address, ETH, AMOUNT);
  });

  it("an unrelated caller cannot initiate escrow from an existing allowance", async function () {
    await expect(
      escrow.connect(stranger).createEscrow(ID, ETH, AMOUNT, stranger.address)
    ).to.be.revertedWith("not NFT owner");
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("an unrelated caller cannot release another user's escrow", async function () {
    await escrow.createEscrow(ID, ETH, AMOUNT, owner.address);
    await expect(escrow.connect(stranger).releaseEscrow(0)).to.be.revertedWith("not escrow creator");
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    await escrow.releaseEscrow(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("settleEscrow cannot claim a non-existent payout or orphan locked ETH", async function () {
    await escrow.createEscrow(ID, ETH, AMOUNT, owner.address);
    await expect(escrow.settleEscrow(0)).to.be.revertedWith("settlement not implemented");
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    expect((await escrow.escrows(0)).active).to.equal(true);
    await escrow.releaseEscrow(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("a stranger cannot create or release a task bond; settlement is disabled", async function () {
    const bond = await (await ethers.getContractFactory("AgentTaskBond")).deploy(nft.address);
    await bond.deployed();
    await nft.approveReserve(ID, bond.address, ETH, AMOUNT);
    const taskHash = ethers.utils.id("task");
    await expect(bond.connect(stranger).createTaskBond(ID, ETH, AMOUNT, owner.address, taskHash))
      .to.be.revertedWith("not NFT owner");
    await bond.createTaskBond(ID, ETH, AMOUNT, owner.address, taskHash);
    await expect(bond.connect(stranger).releaseTaskBond(0)).to.be.revertedWith("not bond creator");
    await expect(bond.settleTaskBond(0)).to.be.revertedWith("settlement not implemented");
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    await bond.releaseTaskBond(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("a stranger cannot open or close another user's demo loan", async function () {
    const lending = await (await ethers.getContractFactory("MinimalLendingCollateral")).deploy(nft.address);
    await lending.deployed();
    await nft.approveReserve(ID, lending.address, ETH, AMOUNT);
    await expect(lending.connect(stranger).openLoan(ID, ETH, AMOUNT))
      .to.be.revertedWith("not NFT owner");
    await lending.openLoan(ID, ETH, AMOUNT);
    await expect(lending.connect(stranger).closeLoan(0)).to.be.revertedWith("not loan creator");
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    await lending.closeLoan(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });
});
