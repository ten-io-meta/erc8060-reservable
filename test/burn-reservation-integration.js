const { expect } = require("chai");
const { ethers } = require("hardhat");

// Local test harness. It reports backing through valueOf even if burn is blocked:
// tests document the semantic conflict; they do NOT establish ERC compliance.
describe("ERC-8060 / Reservable - ETH-backed burn integration", function () {
  const tokenId = 1;
  const ETH = ethers.constants.AddressZero;
  const eth = (n) => ethers.utils.parseEther(n);
  let seller, reservingApp, buyer, nft;

  async function expectRevert(promise) {
    let reverted = false;
    try { await promise; } catch (e) { reverted = true; }
    expect(reverted).to.equal(true);
  }

  beforeEach(async function () {
    [seller, reservingApp, buyer] = await ethers.getSigners();
    const Harness = await ethers.getContractFactory("ERC8060ReservableBurnHarness");
    nft = await Harness.deploy({ value: eth("1") });
    await nft.deployed();
  });

  it("can burn and redeem exactly 1 ETH when nothing is reserved", async function () {
    expect((await nft["valueOf(uint256)"](tokenId)).toString()).to.equal(eth("1").toString());
    expect((await ethers.provider.getBalance(nft.address)).toString()).to.equal(eth("1").toString());
    await nft.burn(tokenId);
    expect((await ethers.provider.getBalance(nft.address)).toString()).to.equal("0");
    await expectRevert(nft["valueOf(uint256)"](tokenId));
    await expectRevert(nft.burn(tokenId));
  });

  it("reproduces Dmitry's case: 1 ETH reported, 0.01 reserved, burn blocked", async function () {
    await nft.approveReserve(tokenId, reservingApp.address, ETH, eth("0.01"));
    await nft.connect(reservingApp).reserveValue(tokenId, ETH, eth("0.01"));
    expect((await nft["valueOf(uint256)"](tokenId)).toString()).to.equal(eth("1").toString());
    expect((await nft.lockedValue(tokenId, ETH)).toString()).to.equal(eth("0.01").toString());
    expect((await nft.availableValue(tokenId, ETH)).toString()).to.equal(eth("0.99").toString());
    await expectRevert(nft.burn(tokenId));
    // A rejected burn must not destroy the token or change the actual ETH backing.
    expect((await nft.ownerOf(tokenId)).toString()).to.equal(seller.address);
    expect((await ethers.provider.getBalance(nft.address)).toString()).to.equal(eth("1").toString());
  });

  it("permits full redemption once the active reservation has been released", async function () {
    await nft.approveReserve(tokenId, reservingApp.address, ETH, eth("0.01"));
    await nft.connect(reservingApp).reserveValue(tokenId, ETH, eth("0.01"));
    await expectRevert(nft.burn(tokenId));
    await nft.connect(reservingApp).releaseValue(tokenId, ETH, eth("0.01"));
    await nft.burn(tokenId);
    expect((await ethers.provider.getBalance(nft.address)).toString()).to.equal("0");
  });

  it("shows the marketplace hazard: buyer inherits an active 0.01 ETH reservation", async function () {
    // A marketplace might read valueOf() here before a seller changes reserve state.
    expect((await nft["valueOf(uint256)"](tokenId)).toString()).to.equal(eth("1").toString());
    await nft.approveReserve(tokenId, reservingApp.address, ETH, eth("0.01"));
    await nft.connect(reservingApp).reserveValue(tokenId, ETH, eth("0.01"));
    await nft.transferFrom(seller.address, buyer.address, tokenId);
    expect((await nft.ownerOf(tokenId)).toString()).to.equal(buyer.address);
    expect((await nft.lockedValue(tokenId, ETH)).toString()).to.equal(eth("0.01").toString());
    expect((await nft["valueOf(uint256)"](tokenId)).toString()).to.equal(eth("1").toString());
    await expectRevert(nft.connect(buyer).burn(tokenId));
    // The reserving application can release the old reservation after transfer.
    await nft.connect(reservingApp).releaseValue(tokenId, ETH, eth("0.01"));
    await nft.connect(buyer).burn(tokenId);
    expect((await ethers.provider.getBalance(nft.address)).toString()).to.equal("0");
  });

  it("cancels unused old allowances on transfer without touching active locks", async function () {
    await nft.approveReserve(tokenId, reservingApp.address, ETH, eth("0.02"));
    await nft.connect(reservingApp).reserveValue(tokenId, ETH, eth("0.01"));
    await nft.transferFrom(seller.address, buyer.address, tokenId);
    expect((await nft.reserveAllowance(tokenId, reservingApp.address, ETH)).toString()).to.equal("0");
    expect((await nft.lockedValue(tokenId, ETH)).toString()).to.equal(eth("0.01").toString());
    await expectRevert(nft.connect(reservingApp).reserveValue(tokenId, ETH, eth("0.01")));
    await nft.connect(reservingApp).releaseValue(tokenId, ETH, eth("0.01"));
    expect((await nft.availableValue(tokenId, ETH)).toString()).to.equal(eth("1").toString());
  });
});


