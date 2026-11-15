const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC8060 marketplace - atomic buyer protection", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const ONE = ethers.utils.parseEther("1");
  const LOCK = ethers.utils.parseEther("0.01");
  const PRICE = ethers.utils.parseEther("0.4");

  let seller, reserver, buyer, other, strict, conditional, market;

  async function reverted(promise) {
    let didRevert = false;
    try { await promise; } catch (e) { didRevert = true; }
    expect(didRevert).to.equal(true);
  }

  beforeEach(async function () {
    [seller, reserver, buyer, other] = await ethers.getSigners();
    strict = await (await ethers.getContractFactory("ERC8060StrictProfileLab"))
      .deploy({ value: ONE });
    await strict.deployed();
    conditional = await (await ethers.getContractFactory("ERC8060ConditionalProfileLab"))
      .deploy({ value: ONE });
    await conditional.deployed();
    market = await (await ethers.getContractFactory("ERC8060MarketplaceLab")).deploy();
    await market.deployed();
  });

  async function listed(nft) {
    await nft.approve(market.address, ID);
    await market.list(nft.address, ID, PRICE);
  }

  async function reserve() {
    await conditional.approveReserve(ID, reserver.address, ETH, LOCK);
    await conditional.connect(reserver).reserveValue(ID, ETH, LOCK);
  }

  it("naive: a seller can reserve AFTER listing and sell an unburnable NFT", async function () {
    await listed(conditional);
    await reserve();
    await market.connect(buyer).buyNaive(conditional.address, ID, { value: PRICE });
    expect(await conditional.ownerOf(ID)).to.equal(buyer.address);
    expect((await conditional.lockedValue(ID, ETH)).eq(LOCK)).to.equal(true);
    await reverted(conditional.connect(buyer).callStatic.burn(ID));
  });

  it("guard: reservation added AFTER listing blocks the sale at execution", async function () {
    await listed(conditional);
    await reserve();
    await reverted(market.connect(buyer).buyConditionalLab(conditional.address, ID, ONE, { value: PRICE }));
    expect(await conditional.ownerOf(ID)).to.equal(seller.address);
    expect((await ethers.provider.getBalance(market.address)).isZero()).to.equal(true);
    const l = await market.listings(conditional.address, ID);
    expect(l.seller).to.equal(seller.address);
  });

  it("guard: releasing the reservation allows the buyer to buy and burn", async function () {
    await listed(conditional);
    await reserve();
    await reverted(market.connect(buyer).buyConditionalLab(conditional.address, ID, ONE, { value: PRICE }));
    await conditional.connect(reserver).releaseValue(ID, ETH, LOCK);
    await market.connect(buyer).buyConditionalLab(conditional.address, ID, ONE, { value: PRICE });
    expect(await conditional.ownerOf(ID)).to.equal(buyer.address);
    await conditional.connect(buyer).burn(ID);
    expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
  });

  it("strict: recognized ERC8060 sale succeeds with a buyer's minimum", async function () {
    await listed(strict);
    await market.connect(buyer).buyStrict(strict.address, ID, ONE, { value: PRICE });
    expect(await strict.ownerOf(ID)).to.equal(buyer.address);
    await strict.connect(buyer).burn(ID);
    expect((await ethers.provider.getBalance(strict.address)).isZero()).to.equal(true);
  });

  it("strict: an insufficient value relative to buyer's minimum is rejected", async function () {
    await listed(strict);
    await reverted(market.connect(buyer).buyStrict(strict.address, ID, ONE.add(1), { value: PRICE }));
    expect(await strict.ownerOf(ID)).to.equal(seller.address);
  });

  it("profiles: a conditional NFT cannot pass the strict interface check", async function () {
    await listed(conditional);
    await reverted(market.connect(buyer).buyStrict(conditional.address, ID, ONE, { value: PRICE }));
    expect(await conditional.ownerOf(ID)).to.equal(seller.address);
  });

  it("profiles: a strict NFT cannot masquerade as the conditional profile", async function () {
    await listed(strict);
    await reverted(market.connect(buyer).buyConditionalLab(strict.address, ID, ONE, { value: PRICE }));
    expect(await strict.ownerOf(ID)).to.equal(seller.address);
  });

  it("stale listing: settlement rechecks the current owner", async function () {
    await listed(strict);
    await strict.transferFrom(seller.address, other.address, ID);
    await reverted(market.connect(buyer).buyStrict(strict.address, ID, ONE, { value: PRICE }));
    expect(await strict.ownerOf(ID)).to.equal(other.address);
  });

  it("payment: incorrect amount is rejected before the NFT transfer", async function () {
    await listed(strict);
    await reverted(market.connect(buyer).buyStrict(strict.address, ID, ONE, { value: ethers.utils.parseEther("0.1") }));
    expect(await strict.ownerOf(ID)).to.equal(seller.address);
  });
});
