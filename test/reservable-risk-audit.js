const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Reservable - auditoria de contratos demo", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const AMOUNT = ethers.utils.parseEther("0.3");
  let owner, stranger, nft, escrow;

  beforeEach(async function () {
    [owner, stranger] = await ethers.getSigners();

    nft = await (await ethers.getContractFactory(
      "ERC8060ReservableMock"
    )).deploy();
    await nft.deployed();
    await nft.mintValue(ID, ETH, ethers.utils.parseEther("1"));

    escrow = await (await ethers.getContractFactory(
      "MinimalReservableEscrow"
    )).deploy(nft.address);
    await escrow.deployed();

    await nft.approveReserve(ID, escrow.address, ETH, AMOUNT);
  });

  it("tercero puede iniciar reserva usando permiso existente", async function () {
    await escrow.connect(stranger).createEscrow(
      ID, ETH, AMOUNT, stranger.address
    );
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
  });

  it("tercero puede liberar escrow sin autorizacion", async function () {
    await escrow.createEscrow(ID, ETH, AMOUNT, owner.address);
    await escrow.connect(stranger).releaseEscrow(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("settleEscrow deja reserva sin via de liberacion", async function () {
    await escrow.createEscrow(ID, ETH, AMOUNT, owner.address);
    await escrow.settleEscrow(0);
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);

    let blocked = false;
    try { await escrow.callStatic.releaseEscrow(0); }
    catch (e) { blocked = true; }
    expect(blocked).to.equal(true);
  });

  it("tercero puede cerrar garantia de agente", async function () {
    const bond = await (await ethers.getContractFactory(
      "AgentTaskBond"
    )).deploy(nft.address);
    await bond.deployed();
    await nft.approveReserve(ID, bond.address, ETH, AMOUNT);
    await bond.createTaskBond(
      ID, ETH, AMOUNT, owner.address, ethers.utils.id("tarea")
    );
    await bond.connect(stranger).settleTaskBond(0);
    expect((await bond.bonds(0)).settled).to.equal(true);
  });

  it("tercero puede cerrar prestamo y desbloquear garantia", async function () {
    const lending = await (await ethers.getContractFactory(
      "MinimalLendingCollateral"
    )).deploy(nft.address);
    await lending.deployed();
    await nft.approveReserve(ID, lending.address, ETH, AMOUNT);
    await lending.openLoan(ID, ETH, AMOUNT);
    await lending.connect(stranger).closeLoan(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });
});
