const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("AgentTaskBond - autorizacion y vencimiento", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const AMOUNT = ethers.utils.parseEther("0.3");

  let owner, agent, verifier, stranger, nft, bond, deadline;

  async function mustRevert(promise) {
    let reverted = false;
    try { await promise; } catch (e) { reverted = true; }
    expect(reverted).to.equal(true);
  }

  beforeEach(async function () {
    [owner, agent, verifier, stranger] = await ethers.getSigners();

    nft = await (await ethers.getContractFactory(
      "ERC8060ReservableMock"
    )).deploy();
    await nft.deployed();
    await nft.mintValue(ID, ETH, ethers.utils.parseEther("1"));

    bond = await (await ethers.getContractFactory(
      "AgentTaskBondTimedDemo"
    )).deploy(nft.address);
    await bond.deployed();

    await nft.approveReserve(ID, bond.address, ETH, AMOUNT);
    deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;
  });

  async function create() {
    await bond.createBond(
      ID, ETH, AMOUNT, agent.address, verifier.address, deadline
    );
  }

  it("tercero no puede crear garantia", async function () {
    await mustRevert(
      bond.connect(stranger).createBond(
        ID, ETH, AMOUNT, agent.address, verifier.address, deadline
      )
    );
  });

  it("tercero no puede liberar antes del vencimiento", async function () {
    await create();
    await mustRevert(bond.connect(stranger).releaseByVerifier(0));
    await mustRevert(bond.connect(stranger).releaseAfterDeadline(0));
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
  });

  it("verificador autorizado puede liberar", async function () {
    await create();
    await bond.connect(verifier).releaseByVerifier(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("tras vencimiento cualquiera puede desbloquear", async function () {
    await create();
    await network.provider.send("evm_increaseTime", [3601]);
    await network.provider.send("evm_mine");
    await bond.connect(stranger).releaseAfterDeadline(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("transferencia conserva garantia activa", async function () {
    await create();
    await nft.transferFrom(owner.address, stranger.address, ID);
    expect((await nft.lockedValue(ID, ETH)).eq(AMOUNT)).to.equal(true);
    await bond.connect(verifier).releaseByVerifier(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("no puede liberarse dos veces", async function () {
    await create();
    await bond.connect(verifier).releaseByVerifier(0);
    await mustRevert(bond.connect(verifier).releaseByVerifier(0));
  });
});