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
  it("prevents any additional reservation after exact exhaustion", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("exact-exhaustion-test")
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
    300,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");

  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 301);

  try {
    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      1,
      seller.address
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("insufficient available value");
  }

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
});
it("new owner can reserve remaining available value after transfer", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("new-owner-overlap")
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

  await token
    .connect(seller)
    .approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 300);

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    300,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
});
it("old spender cannot reserve more after transfer without sufficient allowance", async function () {
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 100);

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    100,
    seller.address
  );

  await token.transferFrom(owner.address, seller.address, TOKEN_ID);

  expect(await token.ownerOf(TOKEN_ID)).to.equal(seller.address);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");

  try {
    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      1,
      seller.address
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("exceeds reserve allowance");
  }

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
});
it("new owner can withdraw only available value after transfer", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("new-owner-withdraw-available")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await token.transferFrom(owner.address, seller.address, TOKEN_ID);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  await token.connect(seller).withdraw(
    TOKEN_ID,
    ETH_ASSET,
    300
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
});
it("cannot reserve after new owner withdraws all available value", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("withdraw-then-reserve")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await token.transferFrom(owner.address, seller.address, TOKEN_ID);

  await token.connect(seller).withdraw(
    TOKEN_ID,
    ETH_ASSET,
    300
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");

  await token.connect(seller).approveReserve(
    TOKEN_ID,
    escrow.address,
    ETH_ASSET,
    1
  );

  try {
    await escrow.createEscrow(
      TOKEN_ID,
      ETH_ASSET,
      1,
      seller.address
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("insufficient available value");
  }
});
it("active obligations remain releasable after available value is withdrawn", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("withdraw-available-then-release")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    300,
    agent.address,
    TASK_HASH
  );

  await token.transferFrom(owner.address, seller.address, TOKEN_ID);

  await token.connect(seller).withdraw(
    TOKEN_ID,
    ETH_ASSET,
    300
  );

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");

  await bond.releaseTaskBond(0);

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  await lending.closeLoan(0);

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
});
it("release after transfer and partial withdraw preserves accounting", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("transfer-withdraw-release")
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

  await token.connect(seller).withdraw(
    TOKEN_ID,
    ETH_ASSET,
    100
  );

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");

  await escrow.releaseEscrow(0);

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("200");

  await bond.releaseTaskBond(0);

  expect((await token.totalValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("500");
});
it("released value can be reserved again by another application", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 300);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("re-reserve-task")
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
    300,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");

  await escrow.releaseEscrow(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    300,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
});
it("keeps reservations isolated by tokenId", async function () {
  const TOKEN_ID_2 = 2;

  await token.mintToken(TOKEN_ID_2, owner.address);

  await token.mintValue(TOKEN_ID, ETH_ASSET, 1000);
  await token.mintValue(TOKEN_ID_2, ETH_ASSET, 500);

  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID_2, lending.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);
  await lending.openLoan(TOKEN_ID_2, ETH_ASSET, 200);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1600");

  expect((await token.lockedValue(TOKEN_ID_2, ETH_ASSET)).toString()).to.equal("200");
  expect((await token.availableValue(TOKEN_ID_2, ETH_ASSET)).toString()).to.equal("300");
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
it("preserves loan bond and escrow obligations after NFT transfer", async function () {

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
it("loan bond and escrow coexist simultaneously", async function () {

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
    ethers.utils.toUtf8Bytes("three-way-test")
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
    (
      await token.lockedValue(
        TOKEN_ID,
        ETH_ASSET
      )
    ).toString()
  ).to.equal("900");

  expect(
    (
      await token.availableValue(
        TOKEN_ID,
        ETH_ASSET
      )
    ).toString()
  ).to.equal("100");
});
it("releasing escrow does not affect loan or task bond", async function () {

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
    ethers.utils.toUtf8Bytes("escrow-release-test")
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

  await escrow.releaseEscrow(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(true);
  expect(taskBond.active).to.equal(true);
  expect(activeEscrow.active).to.equal(false);
});
it("settling escrow does not affect loan or task bond", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("escrow-settle-test")
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

  await escrow.settleEscrow(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(true);
  expect(taskBond.active).to.equal(true);
  expect(activeEscrow.active).to.equal(false);
  expect(activeEscrow.settled).to.equal(true);
});
it("releasing task bond does not affect loan or escrow", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("bond-release-test")
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

  await bond.releaseTaskBond(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("600");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(true);
  expect(taskBond.active).to.equal(false);
  expect(activeEscrow.active).to.equal(true);
});
it("settling task bond does not affect loan or escrow", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("bond-settle-test")
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

  await bond.settleTaskBond(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("900");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");

  const loan = await lending.loans(0);
  const taskBond = await bond.bonds(0);
  const activeEscrow = await escrow.escrows(0);

  expect(loan.active).to.equal(true);
  expect(taskBond.active).to.equal(false);
  expect(taskBond.settled).to.equal(true);
  expect(activeEscrow.active).to.equal(true);
});
it("fully releases independent obligations back to available value", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 300);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("full-release-test")
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

  await escrow.releaseEscrow(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  await bond.releaseTaskBond(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("600");

  await lending.closeLoan(0);

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
});
it("keeps reservations isolated by asset on the same token", async function () {
  const USDC_ASSET = "0x0000000000000000000000000000000000000001";

  await token.mintValue(TOKEN_ID, USDC_ASSET, 500);

  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 400);
  await token.approveReserve(TOKEN_ID, bond.address, USDC_ASSET, 200);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 400);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("multi-asset-task")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    USDC_ASSET,
    200,
    agent.address,
    TASK_HASH
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("400");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("600");

  expect((await token.lockedValue(TOKEN_ID, USDC_ASSET)).toString()).to.equal("200");
  expect((await token.availableValue(TOKEN_ID, USDC_ASSET)).toString()).to.equal("300");
});
it("handles many small independent reservations correctly", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 100);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 100);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 100);

  // 1 loan = 100
  await lending.openLoan(TOKEN_ID, ETH_ASSET, 100);

  // 1 bond = 100
  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("stress-task")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    100,
    agent.address,
    TASK_HASH
  );

  // 1 escrow = 100
  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    100,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("700");

  await escrow.releaseEscrow(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("200");

  await bond.releaseTaskBond(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");

  await lending.closeLoan(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
});
it("release order does not affect final accounting", async function () {
  await token.approveReserve(TOKEN_ID, lending.address, ETH_ASSET, 100);
  await token.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 100);
  await token.approveReserve(TOKEN_ID, escrow.address, ETH_ASSET, 100);

  await lending.openLoan(TOKEN_ID, ETH_ASSET, 100);

  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("release-order-test")
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    100,
    agent.address,
    TASK_HASH
  );

  await escrow.createEscrow(
    TOKEN_ID,
    ETH_ASSET,
    100,
    seller.address
  );

  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("300");

  await lending.closeLoan(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("200");

  await escrow.releaseEscrow(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("100");

  await bond.releaseTaskBond(0);
  expect((await token.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
  expect((await token.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("1000");
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