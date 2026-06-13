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

    expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(eth("60").toString());
    expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(eth("40").toString());
  });

  it("releases locked value back to available value", async function () {
    await mock.approveReserve(TOKEN_ID, escrowA.address, ETH, eth("60"));
    await mock.connect(escrowA).reserveValue(TOKEN_ID, ETH, eth("60"));

    await mock.connect(escrowA).releaseValue(TOKEN_ID, ETH, eth("20"));

    expect((await mock.lockedValue(TOKEN_ID, ETH)).toString()).to.equal(eth("40").toString());
    expect((await mock.availableValue(TOKEN_ID, ETH)).toString()).to.equal(eth("60").toString());
  });
});