const { expect } = require("chai");
const { ethers, network } = require("hardhat");

const ETH = ethers.constants.AddressZero;
const HALF = ethers.utils.parseEther("0.5");
const ONE = ethers.utils.parseEther("1");
const TERMS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(
  "reservation ends at accepted expiry; no beneficiary payment guaranteed"
));
const OTHER_TERMS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("altered terms"));

async function mustRevert(promise, reason) {
  let failed;
  try { await promise; } catch (error) { failed = error; }
  expect(failed, "expected a revert").to.exist;
  if (reason) expect(failed.message).to.include(reason);
}

describe("BilateralTimeboundReserve — bilateral protection and expiry", function () {
  let owner, beneficiary, buyer, outsider, nft, app;

  beforeEach(async function () {
    [owner, beneficiary, buyer, outsider] = await ethers.getSigners();
    nft = await (await ethers.getContractFactory("ReservableConditionalETHReference")).deploy();
    await nft.deployed();
    app = await (await ethers.getContractFactory("BilateralTimeboundReserve")).deploy(nft.address);
    await app.deployed();
  });

  async function offer({amount=HALF, expiresIn=200, approved=true}={}) {
    await nft.connect(owner).mint({ value: ONE });
    if (approved) {
      await nft.connect(owner).approveReserve(1, app.address, ETH, amount);
    }
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const deadline = now + expiresIn;
    await app.connect(owner).propose(1, amount, beneficiary.address, deadline, TERMS);
    return deadline;
  }

  it("locks only after matching beneficiary acceptance; owner cannot cancel, release or spend locked funds", async function () {
    await offer();
    expect((await nft.lockedValue(1, ETH)).isZero()).to.equal(true);
    await mustRevert(app.connect(owner).accept(1, TERMS), "not beneficiary");
    await mustRevert(app.connect(beneficiary).accept(1, OTHER_TERMS), "terms mismatch");
    await app.connect(beneficiary).accept(1, TERMS);

    expect((await nft.lockedValue(1, ETH)).eq(HALF)).to.equal(true);
    await mustRevert(app.connect(owner).cancelPending(1), "not proposed");
    await mustRevert(app.connect(owner).releaseEarly(1), "not beneficiary");
    await mustRevert(nft.connect(owner).releaseValue(1, ETH, HALF), "release exceeds allocation");
    await mustRevert(nft.connect(owner).withdrawAvailable(1, ONE), "insufficient available");
    await mustRevert(nft.connect(owner).redeemWhenUnlocked(1), "active reservation blocks redemption");
    expect((await ethers.provider.getBalance(nft.address)).eq(ONE)).to.equal(true);
  });

  it("owner transfer preserves beneficiary rights; outsider can release at exact expiry and buyer can redeem", async function () {
    const deadline = await offer();
    await app.connect(beneficiary).accept(1, TERMS);
    await nft.connect(owner).transferFrom(owner.address, buyer.address, 1);
    await mustRevert(app.connect(outsider).releaseExpired(1), "deadline not reached");

    await network.provider.send("evm_setNextBlockTimestamp", [deadline]);
    await app.connect(outsider).releaseExpired(1);
    expect((await nft.lockedValue(1, ETH)).isZero()).to.equal(true);
    expect((await nft.availableValue(1, ETH)).eq(ONE)).to.equal(true);
    await mustRevert(app.connect(outsider).releaseExpired(1), "not active");

    await nft.connect(buyer).redeemWhenUnlocked(1);
    expect((await ethers.provider.getBalance(nft.address)).isZero()).to.equal(true);
    expect((await nft.totalBacked()).isZero()).to.equal(true);
  });

  it("beneficiary can release early; owner cannot impersonate or extend it", async function () {
    await offer();
    await app.connect(beneficiary).accept(1, TERMS);
    await mustRevert(app.connect(buyer).releaseEarly(1), "not beneficiary");
    await app.connect(beneficiary).releaseEarly(1);
    expect((await nft.lockedValue(1, ETH)).isZero()).to.equal(true);
    await mustRevert(app.connect(beneficiary).releaseEarly(1), "not active");
    await nft.connect(owner).redeemWhenUnlocked(1);
    expect((await ethers.provider.getBalance(nft.address)).isZero()).to.equal(true);
  });

  it("unaccepted proposals can be cancelled; missing approval and pre-acceptance transfer block activation", async function () {
    await offer({approved:false});
    await mustRevert(app.connect(beneficiary).accept(1, TERMS), "insufficient reserve allowance");
    await app.connect(owner).cancelPending(1);
    await mustRevert(app.connect(beneficiary).accept(1, TERMS), "not proposed");

    const now = (await ethers.provider.getBlock("latest")).timestamp;
    await nft.connect(owner).approveReserve(1, app.address, ETH, HALF);
    await app.connect(owner).propose(1, HALF, beneficiary.address, now + 1000, TERMS);
    await nft.connect(owner).transferFrom(owner.address, buyer.address, 1);
    await mustRevert(app.connect(beneficiary).accept(2, TERMS), "owner changed");
    expect((await nft.lockedValue(1, ETH)).isZero()).to.equal(true);
  });
});
