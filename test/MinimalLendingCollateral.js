const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MinimalLendingCollateral", function () {
  let owner;
  let agent;
  let seller;

  let token;
  let lending;
  let bond;
  let escrow;

  const TOKEN_ID = 1;
  const ETH_ASSET = ethers.constants.AddressZero;
  const TOTAL_VALUE = ethers.BigNumber.from("1000");

  beforeEach(async function () {
    [owner, agent, seller] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("ERC8060ReservableMock");
    token = await Token.deploy();
    await token.deployed();

    await token.mintValue(TOKEN_ID, ETH_ASSET, TOTAL_VALUE);

    const Lending = await ethers.getContractFactory("MinimalLendingCollateral");
    lending = await Lending.deploy(token.address);
    await lending.deployed();

    const Bond = await ethers.getContractFactory("AgentTaskBond");
    bond = await Bond.deploy(token.address);
    await bond.deployed();

    const Escrow = await ethers.getContractFactory("MinimalReservableEscrow");
    escrow = await Escrow.deploy(token.address);
    await escrow.deployed();
  });

  it("lending and task bonds coexist on the same token", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-1")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
    expect(await token.ownerOf(TOKEN_ID)).to.equal(owner.address);
  });

  it("three independent applications can reserve value on the same token", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
    await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-2")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      200,
      seller.address
    );

    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");
  });

  it("prevents over-allocation across independent applications", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
    await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 400);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-3")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    try {
      await escrow.createEscrow(
        TOKEN_ID,
        ETH_ASSET,
        400,
        seller.address
      );

      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include("insufficient available value");
    }

    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
  });

  it("preserves active obligations after NFT transfer", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-transfer")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    await token.transferFrom(owner.address, seller.address, TOKEN_ID);

    expect(await token.ownerOf(TOKEN_ID)).to.equal(seller.address);
    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
  });

  it("preserves three active obligations after NFT transfer", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
    await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-transfer-three")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      200,
      seller.address
    );

    await token.transferFrom(owner.address, seller.address, TOKEN_ID);

    expect(await token.ownerOf(TOKEN_ID)).to.equal(seller.address);
    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");
  });

  it("new owner cannot withdraw locked value after transfer", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-with-transfer")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    await token.transferFrom(owner.address, seller.address, TOKEN_ID);

    try {
      await token.connect(seller).withdraw(
        TOKEN_ID,
        ETH_ASSET,
        1000
      );

      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include("insufficient available value");
    }

    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
  });
  it("closing loan does not affect escrow or task bond", async function () {

  await token.approveReserve(
    TOKEN_ID,
    lending.address,
    ETH_ASSET,
    400
  );

  await token.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    300
  );

  await token.approveReserve(
    TOKEN_ID,
    escrow.address,
    ETH_ASSET,
    200
  );

  await lending.openLoan(
    TOKEN_ID,
    ETH_ASSET,
    400
  );

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("task-independent")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    200,
    seller.address
  );

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("900");

  await lending.closeLoan(0);

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("500");

  expect(
    (await token.availableValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("500");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(false);
  expect(loan.closed).to.equal(true);

  expect(taskBond.active).to.equal(true);
  expect(activeEscrow.active).to.equal(true);
});
it("preserves three active obligations after NFT transfer", async function () {

  await token.approveReserve(
    TOKEN_ID,
    lending.address,
    ETH_ASSET,
    400
  );

  await token.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    300
  );

  await token.approveReserve(
    TOKEN_ID,
    escrow.address,
    ETH_ASSET,
    200
  );

  await lending.openLoan(
    TOKEN_ID,
    ETH_ASSET,
    400
  );

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("task-transfer-3")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    200,
    seller.address
  );

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("900");

  expect(
    (await token.availableValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("100");

  await token.transferFrom(
    owner.address,
    seller.address,
    TOKEN_ID
  );

  expect(
    await token.ownerOf(TOKEN_ID)
  ).to.equal(seller.address);

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("900");

  expect(
    (await token.availableValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("100");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(true);
  expect(taskBond.active).to.equal(true);
  expect(activeEscrow.active).to.equal(true);
});
it("independent applications release collateral independently", async function () {

  await token.approveReserve(
    TOKEN_ID,
    lending.address,
    ETH_ASSET,
    400
  );

  await token.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    300
  );

  await token.approveReserve(
    TOKEN_ID,
    escrow.address,
    ETH_ASSET,
    200
  );

  await lending.openLoan(
    TOKEN_ID,
    ETH_ASSET,
    400
  );

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("task-release")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    200,
    seller.address
  );

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("900");

  await escrow.releaseEscrow(0);

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("700");

  await lending.closeLoan(0);

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("300");

  await bond.releaseTaskBond(0);

  expect(
    (await token.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("0");

  expect(
    (await token.availableValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("1000");
});
  it("closing a loan releases only its own collateral", async function () {
    await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
    await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

    await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

    const TASK_HASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-close-loan")
    );

    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      300,
      agent.address,
      TASK_HASH
    );

    await lending.closeLoan(0);

    expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
    expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");

    const loan = await lending.loans(0);
    const taskBond = await bond.bonds(0);

    expect(loan.active).to.equal(false);
    expect(loan.closed).to.equal(true);
    expect(taskBond.active).to.equal(true);
  });
});