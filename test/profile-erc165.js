const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC8060 profile discovery - ERC721 and ERC165", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const ONE = ethers.utils.parseEther("1");
  const PART = ethers.utils.parseEther("0.01");
  const ERC721_ID = "0x80ac58cd";
  const ERC165_ID = "0x01ffc9a7";
  const ERC8060_ID = "0x88495fe7";

  function reservableInterfaceId() {
    const signatures = [
      "approveReserve(uint256,address,address,uint256)",
      "reserveValue(uint256,address,uint256)",
      "releaseValue(uint256,address,uint256)",
      "reserveAllowance(uint256,address,address)",
      "lockedValue(uint256,address)",
      "availableValue(uint256,address)"
    ];
    const value = signatures.reduce(
      (acc, sig) => (acc ^ parseInt(ethers.utils.id(sig).slice(0, 10), 16)) >>> 0,
      0
    );
    return "0x" + value.toString(16).padStart(8, "0");
  }

  let strict, conditional, owner, app, buyer;
  beforeEach(async function () {
    [owner, app, buyer] = await ethers.getSigners();
    const A = await ethers.getContractFactory("ERC8060StrictProfileLab");
    strict = await A.deploy({ value: ONE });
    await strict.deployed();
    const B = await ethers.getContractFactory("ERC8060ConditionalProfileLab");
    conditional = await B.deploy({ value: ONE });
    await conditional.deployed();
  });

  async function reserve() {
    await conditional.approveReserve(ID, app.address, ETH, PART);
    await conditional.connect(app).reserveValue(ID, ETH, PART);
  }

  it("strict: advertises ERC165, ERC721 and the draft IERC721Value", async function () {
    expect(await strict.supportsInterface(ERC165_ID)).to.equal(true);
    expect(await strict.supportsInterface(ERC721_ID)).to.equal(true);
    expect(await strict.supportsInterface(ERC8060_ID)).to.equal(true);
    expect(await strict.supportsInterface(reservableInterfaceId())).to.equal(false);
    expect((await strict["valueOf(uint256)"](ID)).eq(ONE)).to.equal(true);
  });

  it("strict: owner burns and receives the exact 1 ETH backing", async function () {
    expect(await strict.ownerOf(ID)).to.equal(owner.address);
    await strict.burn(ID);
    expect((await ethers.provider.getBalance(strict.address)).isZero()).to.equal(true);
    await expectRevert(strict.ownerOf(ID));
    await expectRevert(strict["valueOf(uint256)"](ID));
  });

  it("conditional: ERC721+reservable yes, but does NOT claim strict ERC8060", async function () {
    expect(await conditional.supportsInterface(ERC165_ID)).to.equal(true);
    expect(await conditional.supportsInterface(ERC721_ID)).to.equal(true);
    expect(await conditional.supportsInterface(reservableInterfaceId())).to.equal(true);
    expect(await conditional.supportsInterface(ERC8060_ID)).to.equal(false);
    expect((await conditional["valueOf(uint256)"](ID)).eq(ONE)).to.equal(true);
  });

  it("conditional: 0.01 ETH reservation blocks atomic burn despite 1 ETH backing", async function () {
    await reserve();
    expect((await conditional["valueOf(uint256)"](ID)).eq(ONE)).to.equal(true);
    expect((await conditional.lockedValue(ID, ETH)).eq(PART)).to.equal(true);
    expect((await conditional.availableValue(ID, ETH)).eq(ONE.sub(PART))).to.equal(true);
    await expectRevert(conditional.callStatic.burn(ID));
    expect(await conditional.ownerOf(ID)).to.equal(owner.address);
  });

  it("conditional: release enables full redemption with no reserve leakage", async function () {
    await reserve();
    await conditional.connect(app).releaseValue(ID, ETH, PART);
    expect((await conditional.lockedValue(ID, ETH)).isZero()).to.equal(true);
    await conditional.burn(ID);
    expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
  });

  it("conditional: real ERC721 transfer keeps the lock but revokes stale allowance", async function () {
    await conditional.approveReserve(ID, app.address, ETH, ethers.utils.parseEther("0.03"));
    await conditional.connect(app).reserveValue(ID, ETH, PART);
    await conditional.transferFrom(owner.address, buyer.address, ID);
    expect(await conditional.ownerOf(ID)).to.equal(buyer.address);
    expect((await conditional.lockedValue(ID, ETH)).eq(PART)).to.equal(true);
    expect((await conditional.reserveAllowance(ID, app.address, ETH)).isZero()).to.equal(true);
    await expectRevert(conditional.connect(app).reserveValue(ID, ETH, PART));
    await expectRevert(conditional.connect(buyer).callStatic.burn(ID));
    await conditional.connect(app).releaseValue(ID, ETH, PART);
    await conditional.connect(buyer).burn(ID);
    expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
  });

  it("conditional: a new owner may approve fresh reservation without reviving old approvals", async function () {
    await conditional.approveReserve(ID, app.address, ETH, PART);
    await conditional.transferFrom(owner.address, buyer.address, ID);
    expect((await conditional.reserveAllowance(ID, app.address, ETH)).isZero()).to.equal(true);
    await conditional.connect(buyer).approveReserve(ID, app.address, ETH, PART);
    await conditional.connect(app).reserveValue(ID, ETH, PART);
    expect((await conditional.lockedValue(ID, ETH)).eq(PART)).to.equal(true);
  });

  async function expectRevert(promise) {
    let reverted = false;
    try { await promise; } catch (err) { reverted = true; }
    expect(reverted).to.equal(true);
  }
});
