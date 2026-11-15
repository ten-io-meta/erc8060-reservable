const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("Reservable - prestamo con devolucion real", function () {
  const ID = 1;
  const ETH = ethers.constants.AddressZero;
  const VALUE = ethers.utils.parseEther("1");
  const COLLATERAL = ethers.utils.parseEther("0.3");

  let owner, lender, stranger, nft, loan, deadline;

  async function rejects(p) {
    let failed = false;
    try { await p; } catch (e) { failed = true; }
    expect(failed).to.equal(true);
  }

  beforeEach(async function () {
    [owner, lender, stranger] = await ethers.getSigners();
    nft = await (await ethers.getContractFactory(
      "ERC8060ReservableMock"
    )).deploy();
    await nft.deployed();
    await nft.mintValue(ID, ETH, VALUE);

    loan = await (await ethers.getContractFactory(
      "ReservableRepaymentLoanDemo"
    )).deploy(nft.address);
    await loan.deployed();

    await nft.approveReserve(ID, loan.address, ETH, COLLATERAL);
    deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;
  });

  async function create() {
    await loan.createLoan(
      ID, COLLATERAL, VALUE, lender.address, deadline
    );
  }

  async function fund() {
    await loan.connect(lender).fundLoan(0, { value: VALUE });
  }

  it("un tercero no puede crear el prestamo", async function () {
    await rejects(loan.connect(stranger).createLoan(
      ID, COLLATERAL, VALUE, lender.address, deadline
    ));
  });

  it("solo el prestamista puede financiarlo", async function () {
    await create();
    await rejects(loan.connect(stranger).fundLoan(
      0, { value: VALUE }
    ));
    await rejects(loan.connect(lender).fundLoan(
      0, { value: COLLATERAL }
    ));
  });

  it("el prestatario recibe realmente el ETH", async function () {
    await create();
    const before = await ethers.provider.getBalance(owner.address);
    await fund();
    const after = await ethers.provider.getBalance(owner.address);
    expect(after.sub(before).eq(VALUE)).to.equal(true);
  });

  it("no se puede simular una devolucion sin financiar", async function () {
    await create();
    await rejects(loan.repayLoan(0, { value: VALUE }));
  });

  it("no permite cancelar un prestamo ya financiado", async function () {
    await create();
    await fund();
    await network.provider.send("evm_increaseTime", [3601]);
    await network.provider.send("evm_mine");
    await rejects(loan.cancelUnfunded(0));
    expect((await nft.lockedValue(ID, ETH)).eq(COLLATERAL))
      .to.equal(true);
  });

  it("devolver ETH libera garantia y acredita al prestamista", async function () {
    await create();
    await fund();
    await loan.repayLoan(0, { value: VALUE });
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
    expect((await loan.lenderCredits(lender.address)).eq(VALUE))
      .to.equal(true);
    await rejects(loan.repayLoan(0, { value: VALUE }));
    await loan.connect(lender).withdrawRepayment();
    expect((await loan.lenderCredits(lender.address)).isZero())
      .to.equal(true);
    expect((await ethers.provider.getBalance(loan.address)).isZero())
      .to.equal(true);
  });

  it("un tercero puede pagar la deuda, pero no liberar gratis", async function () {
    await create();
    await fund();
    await rejects(loan.connect(stranger).repayLoan(
      0, { value: COLLATERAL }
    ));
    await loan.connect(stranger).repayLoan(0, { value: VALUE });
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });

  it("una solicitud sin financiar puede cancelarse", async function () {
    await create();
    await loan.connect(lender).cancelUnfunded(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
    await rejects(loan.connect(lender).fundLoan(
      0, { value: VALUE }
    ));
  });

  it("si se transfiere antes de financiar, no se presta", async function () {
    await create();
    await nft.transferFrom(owner.address, stranger.address, ID);
    await rejects(loan.connect(lender).fundLoan(
      0, { value: VALUE }
    ));
    await loan.connect(lender).cancelUnfunded(0);
    expect((await nft.lockedValue(ID, ETH)).isZero()).to.equal(true);
  });
});