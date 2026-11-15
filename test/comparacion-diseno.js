const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Comparacion ERC-8060: estricto vs condicionado", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const wei = (v) => ethers.utils.parseEther(v);

  let nft, owner, app;

  beforeEach(async function () {
    [owner, app] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory(
      "ERC8060ReservableBurnHarness"
    );
    nft = await Factory.deploy({ value: wei("1") });
    await nft.deployed();
  });

  async function valueOf() {
    return nft["valueOf(uint256)"](ID);
  }

  async function reserve() {
    await nft.approveReserve(ID, app.address, ETH, wei("0.01"));
    await nft.connect(app).reserveValue(ID, ETH, wei("0.01"));
  }

  it("A: sin reservas la redencion completa funciona", async function () {
    expect((await valueOf()).eq(wei("1"))).to.equal(true);
    await nft.burn(ID);
    expect((await ethers.provider.getBalance(nft.address)).isZero())
      .to.equal(true);
  });

  it("A: valueOf no detecta una reserva que bloquea burn", async function () {
    const before = await valueOf();
    await reserve();
    const after = await valueOf();

    expect(before.eq(after)).to.equal(true);

    let blocked = false;
    try {
      await nft.callStatic.burn(ID);
    } catch (e) {
      blocked = true;
    }
    expect(blocked).to.equal(true);
  });

  it("B: una aplicacion informada distingue los tres valores", async function () {
    await reserve();

    const backing = await valueOf();
    const locked = await nft.lockedValue(ID, ETH);
    const available = await nft.availableValue(ID, ETH);

    expect(backing.eq(wei("1"))).to.equal(true);
    expect(locked.eq(wei("0.01"))).to.equal(true);
    expect(available.eq(wei("0.99"))).to.equal(true);

    const unblockedByReservations = locked.isZero();
    expect(unblockedByReservations).to.equal(false);
  });

  it("B: una oferta antigua debe revalidar el bloqueo", async function () {
    const initialLocked = await nft.lockedValue(ID, ETH);
    expect(initialLocked.isZero()).to.equal(true);

    await reserve();

    const currentLocked = await nft.lockedValue(ID, ETH);
    expect(currentLocked.isZero()).to.equal(false);

    await nft.connect(app).releaseValue(ID, ETH, wei("0.01"));
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });
});
