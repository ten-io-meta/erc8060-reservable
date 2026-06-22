const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC8060ReservableMock", function () {
  const ETH = "0x0000000000000000000000000000000000000000";
  const TOKEN_ID = 1;

  let mock;
  let owner;
  let escrowA;
  let escrowB;
  let buyer;

  const eth = (amount) => ethers.utils.parseEther(amount);

  async function expectRevert(txPromise) {
    let reverted = false;

    try {
      await txPromise;
    } catch (e) {
      reverted = true;
    }

    expect(reverted).to.equal(true);
  }

  beforeEach(async function () {
    [owner, escrowA, escrowB, buyer] = await ethers.getSigners();

    const Mock = await ethers.getContractFactory("ERC8060ReservableMock");
    mock = await Mock.deploy();
    await mock.deployed();

    await mock.mintValue(TOKEN_ID, ETH, eth("100"));
  });

  it("blocks owner withdraw when value is locked", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("60"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("60"));

    await expectRevert(
      mock.withdraw(TOKEN_ID, ETH, eth("50"))
    );
  });

  it("prevents two escrows from over-reserving the same value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("80"));
    await mock.approveReserve(TOKEN_ID, escrowB.address, ETH, eth("80"));

    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("80"));

    await expectRevert(
      mock.connect(escrowB).reserveValue(TOKEN_ID, ETH, eth("80"))
    );
  });

  it("keeps locked value bound to tokenId after transfer", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("60"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("60"));

    await mock.transferFrom(owner.address, buyer.address, TOKEN_ID);

    await expectRevert(
      mock.connect(buyer).withdraw(TOKEN_ID, ETH, eth("50"))
    );
  });

  it("reducing allowance does not release already locked value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("100"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("60"));

    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, 0);

    expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("60").toString()
    );

    expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("40").toString()
    );
  });

  it("cannot reserve zero value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("1"));

    await expectRevert(
      mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("0"))
    );
  });

  it("cannot release zero value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("1"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("1"));

    await expectRevert(
      mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, eth("0"))
    );
  });

  it("handles max uint256 reserve allowance safely", async function () {
    const max = ethers.constants.MaxUint256;

    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, max);

    expect(
      (await mock.reserveAllowance(TOKEN_ID, escrowA.address, ETH)).toString()
    ).to.equal(max.toString());

    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("1"));

    expect(
      (await mock.reserveAllowance(TOKEN_ID, escrowA.address, ETH)).toString()
    ).to.equal(max.sub(eth("1")).toString());
  });

  it("underlying value inflation increases available value without changing locked value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("40"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("40"));

    await mock.mintValue(TOKEN_ID, ETH, eth("50"));

    expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("40").toString()
    );

    expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("110").toString()
    );
  });
  it("prevents cross-token reserve allowance leakage", async function () {
  const TOKEN_ID_2 = 2;

  await mock.mintToken(TOKEN_ID_2, owner.address);
  await mock.mintValue(TOKEN_ID_2, ETH, eth("100"));

  await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("50"));

  await expectRevert(
    mock.connect(escrowA).reserveValue(TOKEN_ID_2, ETH, eth("10"))
  );

  expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal("0");
  expect((await mock.lockedValue(TOKEN_ID_2, ETH)).toString()).to.equal("0");
});

it("prevents spender from releasing more than its own locked allocation", async function () {
  await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("40"));
  await mock.approveReserve(TOKEN_ID, escrowB.address, ETH, eth("40"));

  await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("40"));
  await mock.connect(escrowB).reserveValue(TOKEN_ID, ETH, eth("40"));

  await expectRevert(
    mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, eth("50"))
  );

  expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(
    eth("80").toString()
  );

  expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(
    eth("20").toString()
  );
});

it("does not leak dust after repeated 1 wei reserve and release cycles", async function () {
  await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("1"));

  for (let i = 0; i < 1000; i++) {
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, 1);
    await mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, 1);
  }

  expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal("0");

  expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(
    eth("100").toString()
  );

  await expectRevert(
    mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, 1)
  );
});

  it("releases locked value back to available value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("60"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("60"));

    await mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, eth("20"));

    expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("40").toString()
    );

    expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(
      eth("60").toString()
    );
  });
});