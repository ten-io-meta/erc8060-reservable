const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MinimalReservableEscrow", function () {
  const TOKEN_ID = 1;
  const ETH_ASSET = ethers.constants.AddressZero;
  const ONE_ETH = ethers.utils.parseEther("1");
  const ESCROW_AMOUNT = ethers.utils.parseEther("0.3");

  let owner, seller;
  let reservable, escrow;

  beforeEach(async function () {
    [owner, seller] = await ethers.getSigners();

    const Reservable = await ethers.getContractFactory("ERC8060ReservableMock");
    reservable = await Reservable.deploy();
    await reservable.deployed();

    const Escrow = await ethers.getContractFactory("MinimalReservableEscrow");
    escrow = await Escrow.deploy(reservable.address);
    await escrow.deployed();

    await reservable.mintValue(TOKEN_ID, ETH_ASSET, ONE_ETH);
  });

  it("creates escrow by locking value without transferring the NFT", async function () {
    await reservable.approveReserve(
      TOKEN_ID,
      escrow.address,
      ETH_ASSET,
      ESCROW_AMOUNT
    );

    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      ESCROW_AMOUNT,
      seller.address
    );

    expect(await reservable.ownerOf(TOKEN_ID)).to.equal(owner.address);

    expect(
      (await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal(ESCROW_AMOUNT.toString());

    expect(
      (await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal(ONE_ETH.sub(ESCROW_AMOUNT).toString());
  });

  it("releases escrow back to available value", async function () {
    await reservable.approveReserve(
      TOKEN_ID,
      escrow.address,
      ETH_ASSET,
      ESCROW_AMOUNT
    );

    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      ESCROW_AMOUNT,
      seller.address
    );

    await escrow.releaseEscrow(0);

    expect(
      (await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal("0");

    expect(
      (await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal(ONE_ETH.toString());
  });

  it("cannot create escrow without reserve allowance", async function () {
    try {
      await escrow.createEscrow(
        TOKEN_ID,
        ETH_ASSET,
        ESCROW_AMOUNT,
        seller.address
      );

      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include("exceeds reserve allowance");
    }
  });

  it("cannot release the same escrow twice", async function () {
    await reservable.approveReserve(
      TOKEN_ID,
      escrow.address,
      ETH_ASSET,
      ESCROW_AMOUNT
    );

    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      ESCROW_AMOUNT,
      seller.address
    );

    await escrow.releaseEscrow(0);

    try {
      await escrow.releaseEscrow(0);
      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include("Escrow not active");
    }

    expect(
      (await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal("0");

    expect(
      (await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()
    ).to.equal(ONE_ETH.toString());
  });

  it("cannot settle after release, because the mock has no payout", async function () {
    await reservable.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, ESCROW_AMOUNT);
    await escrow.createEscrow(TOKEN_ID, ETH_ASSET, ESCROW_AMOUNT, seller.address);
    await escrow.releaseEscrow(0);
    try {
      await escrow.settleEscrow(0);
      expect.fail("Expected unavailable settlement");
    } catch(e) {
      expect(e.message).to.include("escrow payout not implemented");
    }
    const e=await escrow.escrows(0);
    expect(e.active).to.equal(false);
    expect(e.settled).to.equal(false);
  });

  it("fails closed without marking unpaid escrow as settled", async function () {
    await reservable.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, ESCROW_AMOUNT);
    await escrow.createEscrow(TOKEN_ID, ETH_ASSET, ESCROW_AMOUNT, seller.address);
    try { await escrow.settleEscrow(0); expect.fail("Expected unavailable settlement"); }
    catch(e) { expect(e.message).to.include("escrow payout not implemented"); }
    const e=await escrow.escrows(0);
    expect(e.active).to.equal(true);
    expect(e.settled).to.equal(false);
    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString())
      .to.equal(ESCROW_AMOUNT.toString());
  });
});