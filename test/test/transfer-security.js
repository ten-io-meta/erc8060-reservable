
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Reservable - transfer security", function () {
  const tokenId = 1;
  const asset = ethers.constants.AddressZero;
  const eth = (value) => ethers.utils.parseEther(value);

  let mock, seller, spender, buyer;

  beforeEach(async function () {
    [seller, spender, buyer] = await ethers.getSigners();

    const Mock = await ethers.getContractFactory("ERC8060ReservableMock");
    mock = await Mock.deploy();
    await mock.deployed();

    await mock.mintValue(tokenId, asset, eth("1"));
  });

  it("invalidates unused allowances after transfer", async function () {
    await mock.approveReserve(tokenId, spender.address, asset, eth("0.01"));

    await mock.transferFrom(seller.address, buyer.address, tokenId);

    expect(
      (await mock.reserveAllowance(tokenId, spender.address, asset)).toString()
    ).to.equal("0");
  });

  it("prevents new reservations using old permissions", async function () {
    await mock.approveReserve(tokenId, spender.address, asset, eth("0.1"));

    await mock.transferFrom(seller.address, buyer.address, tokenId);

    let reverted = false;
    try {
      await mock.connect(spender).reserveValue(tokenId, asset, eth("0.01"));
    } catch (error) {
      reverted = true;
    }

    expect(reverted).to.equal(true);
    expect((await mock.lockedValue(tokenId, asset)).toString()).to.equal("0");
  });

  it("preserves active reservations and permits their release", async function () {
    await mock.approveReserve(tokenId, spender.address, asset, eth("0.01"));
    await mock.connect(spender).reserveValue(tokenId, asset, eth("0.01"));

    await mock.transferFrom(seller.address, buyer.address, tokenId);

    expect(
      (await mock.lockedValue(tokenId, asset)).toString()
    ).to.equal(eth("0.01").toString());

    expect(
      (await mock.availableValue(tokenId, asset)).toString()
    ).to.equal(eth("0.99").toString());

    await mock.connect(spender).releaseValue(tokenId, asset, eth("0.01"));

    expect((await mock.lockedValue(tokenId, asset)).toString()).to.equal("0");

    expect(
      (await mock.availableValue(tokenId, asset)).toString()
    ).to.equal(eth("1").toString());
  });

  it("allows the new owner to grant fresh permissions", async function () {
    await mock.transferFrom(seller.address, buyer.address, tokenId);

    await mock.connect(buyer).approveReserve(
      tokenId, spender.address, asset, eth("0.02")
    );

    await mock.connect(spender).reserveValue(tokenId, asset, eth("0.02"));

    expect(
      (await mock.lockedValue(tokenId, asset)).toString()
    ).to.equal(eth("0.02").toString());
  });
});
