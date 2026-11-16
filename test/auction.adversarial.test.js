const { expect } = require("chai");
const { ethers, network } = require("hardhat");

const eth = ethers.utils.parseEther;
const OPEN = 10;
const SOLD = 11;
const REPAID = 3;
const LIQUIDATED = 7;
const DAY = 24 * 60 * 60;

async function jump(timestamp) {
  const now = (await ethers.provider.getBlock("latest")).timestamp;
  await network.provider.send("evm_setNextBlockTimestamp", [Math.max(timestamp, now + 1)]);
  await network.provider.send("evm_mine");
}

async function mustRevert(action) {
  let reverted = false;
  try { await (await action()).wait(); } catch (e) { reverted = true; }
  expect(reverted).to.equal(true);
}

describe("Dutch auction: adversarial regression / experimental only", function () {
  async function setup(fake = false) {
    const [borrower, lender, arbiter, buyerA, buyerB, outsider] = await ethers.getSigners();
    const N = await ethers.getContractFactory(fake ? "AuctionFakeValueNFT" : "ERC8060NativeETHReference");
    const nft = await N.deploy(); await nft.deployed();
    if (fake) await (await nft.connect(borrower).mint()).wait();
    else await (await nft.connect(borrower).mint({ value: eth("2") })).wait();
    const C = await ethers.getContractFactory("CustodiedCollateralLoanPoC");
    const loan = await C.deploy(nft.address); await loan.deployed();
    await (await nft.connect(borrower).approve(loan.address, 1)).wait();
    const t = (await ethers.provider.getBlock("latest")).timestamp;
    const offer = {
      tokenId: 1,
      lender: lender.address,
      arbiter: arbiter.address,
      principal: eth("1"),
      payoff: eth("1.2"),
      fundingDeadline: t + DAY,
      term: 100,
      grace: 0,
      challenge: 10,
      arbitrateFor: 10,
      termsHash: ethers.utils.id("adversarial-auction-v2"),
      saleStartPrice: eth("3"),
      saleDuration: 3600
    };
    await (await loan.connect(borrower).propose(offer)).wait();
    await (await loan.connect(lender).fund(1, offer.termsHash, { value: offer.principal })).wait();
    const active = await loan.loanInfo(1);
    await jump(active.dueAt.toNumber() + 1);
    await (await loan.connect(outsider).declareDefault(1)).wait();
    const def = await loan.loanInfo(1);
    await jump(def.defaultAt.toNumber() + offer.challenge + 1);
    await (await loan.connect(outsider).startSale(1)).wait();
    return { nft, loan, borrower, lender, arbiter, buyerA, buyerB, outsider, offer };
  }

  it("rejects a reentrant second purchase during the NFT receiver callback", async () => {
    const { nft, loan, buyerA, lender, borrower } = await setup();
    const M = await ethers.getContractFactory("AuctionReentrantReceiver");
    const receiver = await M.deploy(loan.address); await receiver.deployed();
    await (await receiver.setLoanId(1)).wait();
    await (await loan.connect(buyerA).buyCollateral(1, eth("3"), receiver.address, { value: eth("3") })).wait();
    expect(await receiver.attempted()).to.equal(true);
    expect(await receiver.reentrySucceeded()).to.equal(false);
    expect(await nft.ownerOf(1)).to.equal(receiver.address);
    expect((await loan.loanInfo(1)).state).to.equal(SOLD);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    expect(await loan.credits(borrower.address)).to.be.gt(0);
    expect(await loan.isCreditSolvent()).to.equal(true);
  });

  it("rolls back buyer ETH and all credits when recipient refuses the NFT", async () => {
    const { nft, loan, buyerA, borrower, lender } = await setup();
    const M = await ethers.getContractFactory("AuctionRejectingReceiver");
    const receiver = await M.deploy(); await receiver.deployed();
    const beforeCredits = await loan.totalCredits();
    await mustRevert(() => loan.connect(buyerA).buyCollateral(1, eth("3"), receiver.address, { value: eth("3") }));
    expect((await loan.loanInfo(1)).state).to.equal(OPEN);
    expect(await nft.ownerOf(1)).to.equal(loan.address);
    expect(await loan.totalCredits()).to.equal(beforeCredits);
    expect(await loan.credits(borrower.address)).to.equal(0);
    expect(await loan.credits(lender.address)).to.equal(0);
    expect(await loan.isCreditSolvent()).to.equal(true);
  });

  for (const first of ["A", "B"]) {
    it(`only one competing buyer succeeds when ${first} buys first`, async () => {
      const { nft, loan, buyerA, buyerB } = await setup();
      const winner = first === "A" ? buyerA : buyerB;
      const loser = first === "A" ? buyerB : buyerA;
      await (await loan.connect(winner).buyCollateral(1, eth("3"), winner.address, { value: eth("3") })).wait();
      await mustRevert(() => loan.connect(loser).buyCollateral(1, eth("3"), loser.address, { value: eth("3") }));
      expect(await nft.ownerOf(1)).to.equal(winner.address);
      expect((await loan.loanInfo(1)).state).to.equal(SOLD);
      expect(await loan.isCreditSolvent()).to.equal(true);
    });
  }

  it("a valid debt cure before purchase closes sale and saves NFT", async () => {
    const { loan, buyerA, borrower, lender, nft } = await setup();
    await (await loan.connect(borrower).settleAfterDefault(1, { value: eth("1.2") })).wait();
    await mustRevert(() => loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") }));
    expect((await loan.loanInfo(1)).state).to.equal(REPAID);
    expect(await nft.ownerOf(1)).to.equal(loan.address);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    await (await loan.connect(borrower).claimCollateral(1, borrower.address)).wait();
    expect(await nft.ownerOf(1)).to.equal(borrower.address);
  });

  it("purchase before cure closes repayment without double settlement", async () => {
    const { loan, buyerA, borrower, lender, nft } = await setup();
    await (await loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") })).wait();
    await mustRevert(() => loan.connect(borrower).settleAfterDefault(1, { value: eth("1.2") }));
    expect((await loan.loanInfo(1)).state).to.equal(SOLD);
    expect(await nft.ownerOf(1)).to.equal(buyerA.address);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    expect(await loan.isCreditSolvent()).to.equal(true);
  });

  it("preserves maximum price slippage protection and full refund accounting", async () => {
    const { loan, buyerA, borrower, lender, nft } = await setup();
    const started = (await loan.loanInfo(1)).saleStartedAt.toNumber();
    await jump(started + 1800);
    const expected = await loan.currentSalePrice(1);
    expect(expected).to.equal(eth("2.5"));
    await mustRevert(() => loan.connect(buyerA).buyCollateral(1, eth("2.4"), buyerA.address, { value: eth("2.4") }));
    await (await loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") })).wait();
    // No timestamp advance is requested for the purchase; account for the mined block timestamp.
    const purchase = (await loan.queryFilter(loan.filters.NFTSold())).slice(-1)[0].args;
    expect(purchase.price.gte(eth("2"))).to.equal(true);
    expect(purchase.price.lte(eth("3"))).to.equal(true);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    expect(await loan.credits(borrower.address)).to.equal(purchase.borrowerSurplus);
    expect(await loan.credits(buyerA.address)).to.equal(purchase.buyerRefund);
    expect(await loan.totalCredits()).to.equal(eth("3"));
    expect(await nft.ownerOf(1)).to.equal(buyerA.address);
    expect(await loan.isCreditSolvent()).to.equal(true);
  });

  it("sale endpoint: buyer allowed exactly at deadline, burn only after", async () => {
    const { loan, buyerA, nft } = await setup();
    const info = await loan.loanInfo(1);
    const deadline = info.saleStartedAt.toNumber() + info.saleDuration.toNumber();
    await jump(deadline - 2);
    await mustRevert(() => loan.burnUnsold(1));
    // Put the successful BUY in the final permitted timestamp.
    await network.provider.send("evm_setNextBlockTimestamp", [deadline]);
    await (await loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") })).wait();
    expect((await loan.loanInfo(1)).state).to.equal(SOLD);
    expect(await nft.ownerOf(1)).to.equal(buyerA.address);
    await mustRevert(() => loan.burnUnsold(1));
  });

  it("after deadline no buyer may purchase; fallback burn credits real ETH once", async () => {
    const { loan, buyerA, borrower, lender } = await setup();
    const info = await loan.loanInfo(1);
    await jump(info.saleStartedAt.toNumber() + info.saleDuration.toNumber() + 1);
    await mustRevert(() => loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") }));
    await (await loan.burnUnsold(1)).wait();
    expect((await loan.loanInfo(1)).state).to.equal(LIQUIDATED);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    expect(await loan.credits(borrower.address)).to.equal(eth("0.8"));
    expect(await loan.totalCredits()).to.equal(eth("2"));
    expect(await loan.isCreditSolvent()).to.equal(true);
    await mustRevert(() => loan.burnUnsold(1));
  });

  it("fake-value NFT is a documented trust boundary: sale accepts worthless collateral", async () => {
    const { loan, nft, buyerA, lender } = await setup(true);
    // The fake NFT advertises a 2 ETH floor without holding any ETH.
    expect(await ethers.provider.getBalance(nft.address)).to.equal(0);
    await (await loan.connect(buyerA).buyCollateral(1, eth("3"), buyerA.address, { value: eth("3") })).wait();
    expect((await loan.loanInfo(1)).state).to.equal(SOLD);
    expect(await nft.ownerOf(1)).to.equal(buyerA.address);
    expect(await loan.credits(lender.address)).to.equal(eth("1.2"));
    // This proves there is no independent backing verification at sale time.
    // It is a known deployment trust assumption, NOT a security pass.
  });

  it("fake-value NFT cannot fake the ETH amount received from fallback burn", async () => {
    const { loan, nft } = await setup(true);
    const info = await loan.loanInfo(1);
    await jump(info.saleStartedAt.toNumber() + info.saleDuration.toNumber() + 1);
    await mustRevert(() => loan.burnUnsold(1));
    expect((await loan.loanInfo(1)).state).to.equal(OPEN);
    expect(await nft.ownerOf(1)).to.equal(loan.address);
    expect(await loan.totalCredits()).to.equal(0);
  });
});
