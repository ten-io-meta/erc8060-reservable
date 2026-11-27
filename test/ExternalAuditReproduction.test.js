const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * Demonstrates KNOWN UNSAFE DESIGN BOUNDARIES of intentionally incomplete
 * accounting-only examples. Passing = vulnerability reproduced, not fixed.
 * No ETH deposited or transferred; tests run only on local Hardhat.
 */
describe("Reservable mock/adapters — adversarial audit reproduction", function () {
  const asset = ethers.constants.AddressZero;
  let deployer, oldSpender, newOwner, outsider, mock;
  beforeEach(async function () {
    [deployer, oldSpender, newOwner, outsider] = await ethers.getSigners();
    mock = await (await ethers.getContractFactory("ERC8060ReservableMock")).deploy();
    await mock.deployed();
    await mock.mintValue(1, asset, 1000);
  });

  it("UNSAFE: prior owner unused allowance remains executable after holder transfer", async function () {
    await mock.approveReserve(1, oldSpender.address, asset, 200);
    await mock.transferFrom(deployer.address, newOwner.address, 1);
    expect(await mock.ownerOf(1)).to.equal(newOwner.address);
    // A previous owner's unused permission was never renewed by the new owner.
    expect((await mock.reserveAllowance(1, oldSpender.address, asset)).eq(200)).to.equal(true);
    await mock.connect(oldSpender).reserveValue(1, asset, 100);
    expect((await mock.lockedValue(1, asset)).eq(100)).to.equal(true);
    expect((await mock.availableValue(1, asset)).eq(900)).to.equal(true);
    // This is NOT a valid production authorization model.
  });

  it("UNSAFE: any address may mint a new bookkeeping token ID for a recipient", async function () {
    await mock.connect(outsider).mintToken(2, oldSpender.address);
    expect(await mock.ownerOf(2)).to.equal(oldSpender.address);
    expect((await mock.totalValue(2, asset)).eq(0)).to.equal(true);
  });

  it("UNSAFE: escrow can be marked settled by an unrelated caller without any ETH payment", async function () {
    const escrow = await (await ethers.getContractFactory("MinimalReservableEscrow")).deploy(mock.address);
    await escrow.deployed();
    await mock.approveReserve(1, escrow.address, asset, 200);
    await escrow.createEscrow(1, asset, 200, oldSpender.address);
    await escrow.connect(outsider).settleEscrow(0);
    const info = await escrow.escrows(0);
    expect(info.settled).to.equal(true);
    expect(info.active).to.equal(false);
    expect((await mock.lockedValue(1, asset)).eq(200)).to.equal(true);
    expect((await ethers.provider.getBalance(escrow.address)).eq(0)).to.equal(true);
    expect((await ethers.provider.getBalance(mock.address)).eq(0)).to.equal(true);
  });

  it("UNSAFE: unrelated caller may release someone else's active escrow lock", async function () {
    const escrow = await (await ethers.getContractFactory("MinimalReservableEscrow")).deploy(mock.address);
    await escrow.deployed();
    await mock.approveReserve(1, escrow.address, asset, 300);
    await escrow.createEscrow(1, asset, 300, oldSpender.address);
    await escrow.connect(outsider).releaseEscrow(0);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
  });

  it("UNSAFE: third party may mark another user's lending position closed and release lock", async function () {
    const lending = await (await ethers.getContractFactory("MinimalLendingCollateral")).deploy(mock.address);
    await lending.deployed();
    await mock.approveReserve(1, lending.address, asset, 400);
    await lending.connect(oldSpender).openLoan(1, asset, 400);
    const loanBefore = await lending.loans(0);
    expect(loanBefore.borrower).to.equal(oldSpender.address);
    await lending.connect(outsider).closeLoan(0);
    const loanAfter = await lending.loans(0);
    expect(loanAfter.closed).to.equal(true);
    expect((await mock.lockedValue(1, asset)).eq(0)).to.equal(true);
  });
});
