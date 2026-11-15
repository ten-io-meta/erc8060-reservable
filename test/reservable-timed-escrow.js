const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("Reservable - escrow con vencimiento", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const AMOUNT = ethers.utils.parseEther("0.3");
  let owner, beneficiary, stranger, nft, escrow, deadline;

  async function mustRevert(promise) {
    let failed = false;
    try { await promise; } catch (e) { failed = true; }
    expect(failed).to.equal(true);
  }

  beforeEach(async function () {
    [owner, beneficiary, stranger] = await ethers.getSigners();
    nft = await (await ethers.getContractFactory(
      "ERC8060ReservableMock"
    )).deploy();
    await nft.deployed();
    await nft.mintValue(ID, ETH, ethers.utils.parseEther("1"));

    escrow = await (await ethers.getContractFactory(
      "ReservableTimedEscrowDemo"
    )).deploy(nft.address);
    await escrow.deployed();

    await nft.approveReserve(ID, escrow.address, ETH, AMOUNT);
    deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;
  });

  async function create() {
    await escrow.createEscrow(
      ID, ETH, AMOUNT, beneficiary.address, deadline
    );
  }

  it("un tercero no puede crear el escrow", async function () {
    await mustRevert(
      escrow.connect(stranger).createEscrow(
        ID, ETH, AMOUNT, beneficiary.address, deadline
      )
    );
  });

  it("un tercero no puede liberar antes del vencimiento", async function () {
    await create();
    await mustRevert(escrow.connect(stranger).releaseByBeneficiary(0));
    await mustRevert(escrow.connect(stranger).releaseAfterDeadline(0));
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
  });

  it("el beneficiario puede liberar su reserva", async function () {
    await create();
    await escrow.connect(beneficiary).releaseByBeneficiary(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("tras el vencimiento puede desbloquearse", async function () {
    await create();
    await network.provider.send("evm_increaseTime", [3601]);
    await network.provider.send("evm_mine");
    await escrow.connect(stranger).releaseAfterDeadline(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("transferir el NFT no elimina la reserva", async function () {
    await create();
    await nft.transferFrom(owner.address, stranger.address, ID);
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    await mustRevert(escrow.connect(stranger).releaseAfterDeadline(0));
  });
});
