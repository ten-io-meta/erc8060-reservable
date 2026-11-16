const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("ERC8060 - burn fallback after loan default", function () {
  const ETH = ethers.utils.parseEther("1");
  const DEBT = ethers.utils.parseEther("0.3");
  const SURPLUS = ETH.sub(DEBT);
  const DURATION = 3600;
  const GRACE = 86400;
  const TOKEN = 1;

  let borrower, lender, buyer, stranger, nft, vault;

  async function rejects(promise) {
    let failed = false;
    try { await promise; } catch (e) { failed = true; }
    expect(failed).to.equal(true);
  }

  async function advance(seconds) {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
  }

  beforeEach(async function () {
    [borrower, lender, buyer, stranger] =
      await ethers.getSigners();

    nft = await (await ethers.getContractFactory(
      "ERC8060BackedNFTLab"
    )).deploy();
    await nft.deployed();
    await nft.mint({ value: ETH });

    vault = await (await ethers.getContractFactory(
      "ERC8060DefaultBurnLab"
    )).deploy(nft.address);
    await vault.deployed();

    await nft.approve(vault.address, TOKEN);

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    await vault.openLoan(
      TOKEN, lender.address, DEBT, ETH, now + 600, DURATION
    );

    // Separate informed on-chain consent before the lender funds the loan.
    await vault.authorizeBurnFallback(0);
    await vault.connect(lender).fundLoan(0, { value: DEBT });
  });

  it("explicit borrower consent is required, independent of NFT transfer approval", async function () {
    const loan = await vault.loans(0);
    expect(await vault.burnFallbackAuthorized(0)).to.equal(true);
    await rejects(vault.connect(stranger).authorizeBurnFallback(0));
    await matureAndFinishGrace();
    // Authorization was given before funding, so the burn fallback is valid.
    expect(loan.borrower).to.equal(borrower.address);
    await vault.burnDefaultedNFT(0);
  });

  async function matureAndFinishGrace() {
    await advance(DURATION + GRACE + 3);
  }

  it("cannot burn before loan maturity", async function () {
    await rejects(vault.burnDefaultedNFT(0));
    expect(await nft.ownerOf(TOKEN)).to.equal(vault.address);
  });

  it("cannot burn during sale grace period", async function () {
    await advance(DURATION + 2);
    await rejects(vault.burnDefaultedNFT(0));
    expect(await nft.ownerOf(TOKEN)).to.equal(vault.address);
  });

  it("after grace anyone can trigger a fair redemption", async function () {
    await matureAndFinishGrace();
    await vault.connect(stranger).burnDefaultedNFT(0);

    expect((await vault.credits(lender.address)).eq(DEBT))
      .to.equal(true);
    expect((await vault.credits(borrower.address)).eq(SURPLUS))
      .to.equal(true);

    expect((await ethers.provider.getBalance(nft.address)).isZero())
      .to.equal(true);

    await rejects(nft.ownerOf(TOKEN));
  });

  it("both parties can withdraw their recovered ETH", async function () {
    await matureAndFinishGrace();
    await vault.connect(stranger).burnDefaultedNFT(0);

    await vault.connect(lender).withdrawCredit();
    await vault.connect(borrower).withdrawCredit();

    expect((await vault.credits(lender.address)).isZero())
      .to.equal(true);
    expect((await vault.credits(borrower.address)).isZero())
      .to.equal(true);
    expect((await ethers.provider.getBalance(vault.address)).isZero())
      .to.equal(true);
  });

  it("the same collateral cannot be liquidated twice", async function () {
    await matureAndFinishGrace();
    await vault.burnDefaultedNFT(0);
    await rejects(vault.connect(stranger).burnDefaultedNFT(0));
  });

  it("repayment returns the NFT and prevents liquidation", async function () {
    await vault.repayLoan(0, { value: DEBT });
    expect(await nft.ownerOf(TOKEN)).to.equal(borrower.address);

    await matureAndFinishGrace();
    await rejects(vault.burnDefaultedNFT(0));
  });

  it("sale during grace preserves the NFT and prevents burn", async function () {
    await advance(DURATION + 2);

    await vault.connect(buyer).buyDefaultedNFT(
      0, ETH, { value: ETH }
    );

    expect(await nft.ownerOf(TOKEN)).to.equal(buyer.address);

    await advance(GRACE + 3);
    await rejects(vault.burnDefaultedNFT(0));

    expect(
      (await nft["valueOf(uint256)"](TOKEN)).eq(ETH)
    ).to.equal(true);
  });
});