const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentTaskBond", function () {
  const TOKEN_ID = 1;
  const ETH_ASSET = ethers.constants.AddressZero;
  const BOND_AMOUNT = ethers.BigNumber.from("100");
  const TOTAL_VALUE = ethers.BigNumber.from("1000");
  const TASK_HASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("demo-task")
  );

  let owner;
  let agent;
  let reservable;
  let bond;

  async function expectRejected(promise, expected) {
    let error;
    try { await promise; } catch (e) { error = e; }
    expect(error, "expected revert").to.exist;
    expect(error.message).to.include(expected);
  }

  beforeEach(async function () {
    [owner, agent] = await ethers.getSigners();

    const Reservable = await ethers.getContractFactory("ERC8060ReservableMock");
    reservable = await Reservable.deploy();
    await reservable.deployed();

    await reservable.mintValue(TOKEN_ID, ETH_ASSET, TOTAL_VALUE);

    const Bond = await ethers.getContractFactory("AgentTaskBond");
    bond = await Bond.deploy(reservable.address);
    await bond.deployed();

    await reservable.approveReserve(
      TOKEN_ID,
      bond.address,
      ETH_ASSET,
      BOND_AMOUNT
    );
  });

  it("creates task bond by locking value", async function () {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      BOND_AMOUNT,
      agent.address,
      TASK_HASH
    );

    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal(
      BOND_AMOUNT.toString()
    );

    expect((await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal(
      TOTAL_VALUE.sub(BOND_AMOUNT).toString()
    );

    expect(await reservable.ownerOf(TOKEN_ID)).to.equal(owner.address);
  });

  it("releases task bond", async function () {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      BOND_AMOUNT,
      agent.address,
      TASK_HASH
    );

    await bond.releaseTaskBond(0);

    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("0");
    expect((await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal(
      TOTAL_VALUE.toString()
    );
  });

  it("rejects unsupported task settlement without changing the lock", async function () {
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, BOND_AMOUNT, agent.address, TASK_HASH);
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    const info = await bond.bonds(0);
    expect(info.active).to.equal(true);
    expect(info.settled).to.equal(false);
    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).eq(BOND_AMOUNT)).to.equal(true);
  });

  it("can release a bond after a rejected settlement", async function () {
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, BOND_AMOUNT, agent.address, TASK_HASH);
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    await bond.releaseTaskBond(0);
    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).isZero()).to.equal(true);
  });

  it("cannot falsely settle a released task bond", async function () {
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, BOND_AMOUNT, agent.address, TASK_HASH);
    await bond.releaseTaskBond(0);
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).isZero()).to.equal(true);
  });

  it("multiple task bonds accumulate locked value correctly", async function () {

  await reservable.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    500
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    100,
    agent.address,
    ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-1")
    )
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    150,
    agent.address,
    ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes("task-2")
    )
  );

  expect(
    (await reservable.lockedValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("250");

  expect(
    (await reservable.availableValue(
      TOKEN_ID,
      ETH_ASSET
    )).toString()
  ).to.equal("750");
});
it("releasing one task bond does not release other active bonds", async function () {
  await reservable.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    500
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    100,
    agent.address,
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes("task-1"))
  );

  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    150,
    agent.address,
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes("task-2"))
  );

  await bond.releaseTaskBond(0);

  expect(
    (await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()
  ).to.equal("150");

  expect(
    (await reservable.availableValue(TOKEN_ID, ETH_ASSET)).toString()
  ).to.equal("850");

  const first = await bond.bonds(0);
  const second = await bond.bonds(1);

  expect(first.active).to.equal(false);
  expect(second.active).to.equal(true);
});
  it("rejected settlement does not affect concurrent task bonds", async function () {
    await reservable.approveReserve(TOKEN_ID, bond.address, ETH_ASSET, 500);
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, 100, agent.address, ethers.utils.id("one"));
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, 150, agent.address, ethers.utils.id("two"));
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    expect((await reservable.lockedValue(TOKEN_ID, ETH_ASSET)).toString()).to.equal("250");
    const first = await bond.bonds(0);
    const second = await bond.bonds(1);
    expect(first.active).to.equal(true);
    expect(first.settled).to.equal(false);
    expect(second.active).to.equal(true);
  });

it("cannot create task bond with zero amount", async function () {
  try {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      0,
      agent.address,
      TASK_HASH
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("amount is zero");
  }
});
it("cannot create task bond with invalid agent", async function () {
  try {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      BOND_AMOUNT,
      ethers.constants.AddressZero,
      TASK_HASH
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("invalid agent");
  }
});

it("cannot create task bond with empty task hash", async function () {
  try {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      BOND_AMOUNT,
      agent.address,
      ethers.constants.HashZero
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("empty task hash");
  }
});

it("cannot release the same task bond twice", async function () {
  await bond.createTaskBond(
    TOKEN_ID,
    ETH_ASSET,
    BOND_AMOUNT,
    agent.address,
    TASK_HASH
  );

  await bond.releaseTaskBond(0);

  try {
    await bond.releaseTaskBond(0);
    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("bond not active");
  }
});

  it("repeated false settlement attempts never change the bond", async function () {
    await bond.createTaskBond(TOKEN_ID, ETH_ASSET, BOND_AMOUNT, agent.address, TASK_HASH);
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    await expectRejected(bond.settleTaskBond(0), "settlement not implemented");
    expect((await bond.bonds(0)).active).to.equal(true);
  });

  it("cannot create task bond without sufficient available value", async function () {
  await reservable.approveReserve(
    TOKEN_ID,
    bond.address,
    ETH_ASSET,
    ethers.BigNumber.from("2000")
  );

  try {
    await bond.createTaskBond(
      TOKEN_ID,
      ETH_ASSET,
      ethers.BigNumber.from("2000"),
      agent.address,
      TASK_HASH
    );

    expect.fail("Expected transaction to revert");
  } catch (error) {
    expect(error.message).to.include("insufficient available value");
  }
});

  it("cannot create task bond without sufficient reserve allowance", async function () {
    await reservable.approveReserve(
      TOKEN_ID,
      bond.address,
      ETH_ASSET,
      50
    );

    try {
      await bond.createTaskBond(
        TOKEN_ID,
        ETH_ASSET,
        100,
        agent.address,
        TASK_HASH
      );

      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include("exceeds reserve allowance");
    }
  });
});