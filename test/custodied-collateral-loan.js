const { ethers, network } = require("hardhat");
const { expect } = require("chai");

const ETH = ethers.utils.parseEther;
const TERMS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(
  "borrower accepts custodial NFT burn after onchain default, fixed ETH payoff, named arbiter"
));
const INVALID_TERMS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("other terms"));

async function expectRevert(promise, reason) {
  let caught;
  try { await promise; } catch (err) { caught = err; }
  expect(caught, "transaction should revert").to.exist;
  if (reason) expect(caught.message).to.include(reason);
}
const eq = (a, b) => expect(a.eq(b)).to.equal(true);
async function warpAt(ts) {
  await network.provider.send("evm_setNextBlockTimestamp", [ts]);
  await network.provider.send("evm_mine");
}

describe("CustodiedCollateralLoanPoC — money movement and creditor/borrower safety", function () {
  let borrower, lender, arbiter, stranger, collateral, escrow;
  let params;

  beforeEach(async function () {
    [borrower, lender, arbiter, stranger] = await ethers.getSigners();
    collateral = await (await ethers.getContractFactory("ERC8060NativeETHReference")).deploy();
    await collateral.deployed();
    escrow = await (await ethers.getContractFactory("CustodiedCollateralLoanPoC")).deploy(collateral.address);
    await escrow.deployed();
    await collateral.connect(borrower).mint({ value: ETH("2") });
    await collateral.connect(borrower).approve(escrow.address, 1);
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    params = {
      tokenId: 1, lender: lender.address, arbiter: arbiter.address,
      principal: ETH("1"), payoff: ETH("1.1"),
      fundingDeadline: now + 1000,
      term: 200, grace: 100, challenge: 120, arbitrateFor: 120,
      termsHash: TERMS
    };
  });

  async function propose() {
    await escrow.connect(borrower).propose(params);
    expect(await collateral.ownerOf(1)).to.equal(escrow.address);
    return 1;
  }
  async function fund() {
    await escrow.connect(lender).fund(1, TERMS, { value: ETH("1") });
  }
  async function defaultNow() {
    const l = await escrow.loanInfo(1);
    await warpAt(l.dueAt.toNumber() + l.grace.toNumber() + 1);
    await escrow.connect(stranger).declareDefault(1);
  }
  async function afterChallenge() {
    const l = await escrow.loanInfo(1);
    await warpAt(l.defaultAt.toNumber() + l.challenge.toNumber() + 1);
  }

  it("never issues an unfunded debt or accepts wrong principal/terms/lender", async function () {
    await propose();
    await expectRevert(escrow.connect(stranger).fund(1, TERMS, {value:ETH("1")}), "not lender");
    await expectRevert(escrow.connect(lender).fund(1, INVALID_TERMS, {value:ETH("1")}), "terms mismatch");
    await expectRevert(escrow.connect(lender).fund(1, TERMS, {value:ETH("0.9")}), "wrong principal");
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
    await expectRevert(escrow.connect(borrower).claimCollateral(1, borrower.address), "not releasable");
    const before = await ethers.provider.getBalance(borrower.address);
    await fund();
    const after = await ethers.provider.getBalance(borrower.address);
    eq(after.sub(before), ETH("1")); // borrower receives principal atomically
    expect((await escrow.loanInfo(1)).state).to.equal(2); // Active
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
    await expectRevert(escrow.connect(borrower).cancelUnfunded(1, borrower.address), "not proposed");
    await expectRevert(escrow.connect(lender).fund(1, TERMS, { value:ETH("1") }), "not proposed");
  });

  it("fully repaid NFT can return only to borrower or a borrower-chosen recipient", async function () {
    await propose(); await fund();
    await escrow.connect(borrower).repay(1, { value: ETH("0.4") });
    await escrow.connect(stranger).repay(1, { value: ETH("0.7") });
    eq(await escrow.credits(lender.address), ETH("1.1"));
    eq(await escrow.totalCredits(), ETH("1.1"));
    await expectRevert(escrow.connect(stranger).claimCollateral(1, stranger.address), "not borrower");
    await escrow.connect(borrower).claimCollateral(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
    await expectRevert(escrow.connect(borrower).claimCollateral(1, borrower.address), "not releasable");
    await expectRevert(escrow.connect(stranger).declareDefault(1), "not active");
    const before = await ethers.provider.getBalance(stranger.address);
    await escrow.connect(lender).withdrawCredit(stranger.address);
    const after = await ethers.provider.getBalance(stranger.address);
    eq(after.sub(before), ETH("1.1")); // lender chooses payout address
    eq(await escrow.credits(lender.address), ethers.constants.Zero);
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
    await expectRevert(escrow.connect(lender).withdrawCredit(lender.address), "no credit");
  });

  it("default after grace protects lender, burns exact collateral and returns surplus to borrower", async function () {
    await propose(); await fund();
    await escrow.connect(borrower).repay(1, { value: ETH("0.3") });
    await defaultNow();
    await expectRevert(escrow.connect(borrower).repay(1,{value: ETH("0.8")}), "not active");
    await expectRevert(escrow.connect(stranger).liquidate(1), "challenge open");
    await afterChallenge();
    await escrow.connect(stranger).liquidate(1);
    await expectRevert(collateral.ownerOf(1), "invalid token ID");
    eq(await collateral.totalRedeemableValue(), ethers.constants.Zero);
    eq(await ethers.provider.getBalance(collateral.address), ethers.constants.Zero);
    eq(await escrow.credits(lender.address), ETH("1.1")); // 0.3 paid + 0.8 from burn
    eq(await escrow.credits(borrower.address), ETH("1.2"));
    eq(await escrow.totalCredits(), ETH("2.3"));
    eq(await ethers.provider.getBalance(escrow.address), ETH("2.3"));
    await expectRevert(escrow.connect(stranger).liquidate(1), "not liquidatable");
    await escrow.connect(lender).withdrawCredit(lender.address);
    await escrow.connect(borrower).withdrawCredit(borrower.address);
    eq(await escrow.totalCredits(), ethers.constants.Zero);
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
  });

  it("arbiter cannot forgive unpaid debt: only exact onchain payment permits collateral return", async function () {
    await propose(); await fund(); await defaultNow();
    await expectRevert(escrow.connect(arbiter).arbitrate(1,true), "not disputed");
    await escrow.connect(borrower).dispute(1);
    await expectRevert(escrow.connect(stranger).arbitrate(1,true), "not arbiter");
    await expectRevert(escrow.connect(arbiter).arbitrate(1,true), "exact payoff required");
    await expectRevert(escrow.connect(arbiter).arbitrate(1,true, {value:ETH("1")}), "exact payoff required");
    await expectRevert(escrow.connect(arbiter).arbitrate(1,false, {value:ETH("1")}), "no ETH for liquidation");
    expect((await escrow.loanInfo(1)).state).to.equal(5); // Disputed
    await escrow.connect(arbiter).arbitrate(1,true, {value:ETH("1.1")});
    await escrow.connect(borrower).claimCollateral(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
    await expectRevert(escrow.connect(stranger).liquidate(1), "not liquidatable");
    eq(await escrow.credits(lender.address), ETH("1.1")); // proof of actual payment
    eq(await ethers.provider.getBalance(escrow.address), ETH("1.1"));
    expect(await escrow.isCreditSolvent()).to.equal(true);
  });


  it("only lender can voluntarily waive unpaid debt; the arbiter cannot spoof a waiver", async function () {
    await propose(); await fund();
    await escrow.connect(borrower).repay(1, {value:ETH("0.2")});
    await defaultNow();
    await escrow.connect(borrower).dispute(1);
    await expectRevert(escrow.connect(arbiter).lenderWaive(1), "not lender");
    await expectRevert(escrow.connect(borrower).lenderWaive(1), "not lender");
    await expectRevert(escrow.connect(stranger).lenderWaive(1), "not lender");
    await expectRevert(escrow.connect(borrower).claimCollateral(1, borrower.address), "not releasable");
    await escrow.connect(lender).lenderWaive(1);
    expect((await escrow.loanInfo(1)).state).to.equal(6); // Forgiven by creditor
    eq(await escrow.credits(lender.address), ETH("0.2")); // existing credits unaffected
    await escrow.connect(borrower).claimCollateral(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
    await expectRevert(escrow.connect(lender).lenderWaive(1), "not waivable");
    eq(await ethers.provider.getBalance(escrow.address), ETH("0.2"));
  });

  it("any payer can cure default with exact outstanding ETH; liquidator cannot then seize NFT", async function () {
    await propose(); await fund();
    await escrow.connect(borrower).repay(1, {value:ETH("0.3")});
    await defaultNow();
    await escrow.connect(borrower).dispute(1);
    await expectRevert(escrow.connect(stranger).settleAfterDefault(1, {value: ETH("0.7")}), "exact payoff required");
    await escrow.connect(stranger).settleAfterDefault(1, {value: ETH("0.8")});
    eq(await escrow.credits(lender.address), ETH("1.1"));
    eq(await escrow.totalCredits(), ETH("1.1"));
    expect(await escrow.isCreditSolvent()).to.equal(true);
    await expectRevert(escrow.connect(arbiter).arbitrate(1,false), "not disputed");
    await expectRevert(escrow.connect(stranger).liquidate(1), "not liquidatable");
    await escrow.connect(borrower).claimCollateral(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
    await expectRevert(escrow.connect(stranger).settleAfterDefault(1,{value:ETH("0.8")}), "not awaiting resolution");
  });

  it("unfunded or already-liquidated obligations cannot be waived or paid again", async function () {
    await propose();
    await expectRevert(escrow.connect(lender).lenderWaive(1), "not waivable");
    await expectRevert(escrow.connect(stranger).settleAfterDefault(1,{value:ETH("1.1")}), "not awaiting resolution");
    await fund(); await defaultNow(); await afterChallenge();
    await escrow.connect(stranger).liquidate(1);
    await expectRevert(escrow.connect(lender).lenderWaive(1), "not waivable");
    await expectRevert(escrow.connect(arbiter).arbitrate(1,true,{value:ETH("1.1")}), "not disputed");
    eq(await escrow.credits(lender.address), ETH("1.1"));
    eq(await escrow.credits(borrower.address), ETH("0.9"));
  });
  it("arbiter cannot steal ETH, bypass challenge window or redirect liquidation proceeds", async function () {
    await propose(); await fund(); await defaultNow();
    await escrow.connect(lender).dispute(1);
    await expectRevert(escrow.connect(arbiter).arbitrate(1, false), "challenge open");
    await afterChallenge();
    await escrow.connect(arbiter).arbitrate(1, false);
    eq(await escrow.credits(lender.address), ETH("1.1"));
    eq(await escrow.credits(borrower.address), ETH("0.9"));
    eq(await escrow.credits(arbiter.address), ethers.constants.Zero);
    eq(await ethers.provider.getBalance(escrow.address), ETH("2"));
  });

  it("silent arbitrator cannot create an indefinite lock; pre-agreed onchain fallback executes", async function () {
    await propose(); await fund(); await defaultNow();
    await escrow.connect(borrower).dispute(1);
    const l = await escrow.loanInfo(1);
    await warpAt(l.defaultAt.toNumber() + l.challenge.toNumber() + l.arbitrateFor.toNumber() + 1);
    await expectRevert(escrow.connect(arbiter).arbitrate(1,true), "arbitration expired");
    await escrow.connect(stranger).liquidate(1);
    eq(await escrow.credits(lender.address), ETH("1.1"));
    eq(await escrow.credits(borrower.address), ETH("0.9"));
  });

  it("borrower may cancel only before funding and no unrelated wallet can redirect NFT", async function () {
    await propose();
    await expectRevert(escrow.connect(stranger).cancelUnfunded(1, stranger.address), "not borrower");
    await escrow.connect(borrower).cancelUnfunded(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
    await expectRevert(escrow.connect(lender).fund(1, TERMS, { value: ETH("1") }), "not proposed");
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
  });

  it("expired funding cannot activate or trap debt indefinitely; owner can cancel", async function () {
    await propose();
    await warpAt(params.fundingDeadline + 1);
    await expectRevert(escrow.connect(lender).fund(1, TERMS, { value: ETH("1") }), "funding expired");
    await escrow.connect(borrower).cancelUnfunded(1, borrower.address);
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
  });

  it("underfunded redemption floor, forged terms and unauthorized NFT reception fail", async function () {
    params.payoff = ETH("2.1");
    await expectRevert(escrow.connect(borrower).propose(params), "insufficient ETH backing");
    params.payoff = ETH("1.1");
    params.termsHash = ethers.constants.HashZero;
    await expectRevert(escrow.connect(borrower).propose(params), "missing terms");
    await expectRevert(collateral.connect(borrower)["safeTransferFrom(address,address,uint256)"](
      borrower.address,escrow.address,1
    ), "unsolicited NFT");
    expect(await collateral.ownerOf(1)).to.equal(borrower.address);
  });

  it("borrower can repay at deadline+grace boundary but cannot after; dispute window boundary is enforced", async function () {
    await propose(); await fund();
    let l=await escrow.loanInfo(1);
    await network.provider.send("evm_setNextBlockTimestamp", [l.dueAt.toNumber()+l.grace.toNumber()]);
    await escrow.connect(borrower).repay(1,{ value: ETH("0.1") });
    await defaultNow();
    await expectRevert(escrow.connect(stranger).dispute(1), "not a party");
    await escrow.connect(lender).dispute(1);
    await expectRevert(escrow.connect(lender).dispute(1), "not defaulted");
  });
  it("smart-contract borrower rejecting ETH cannot leave a half-funded loan; callback cannot cancel funded collateral", async function () {
    const Probe = await ethers.getContractFactory("LoanBorrowerReceiverProbe");
    const probe = await Probe.deploy(collateral.address, escrow.address);
    await probe.deployed();

    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const contractOffer = {
      tokenId: 2, lender: lender.address, arbiter: arbiter.address,
      principal: ETH("1"), payoff: ETH("1.1"),
      fundingDeadline: now + 1000,
      term: 200, grace: 100, challenge: 120, arbitrateFor: 120,
      termsHash: TERMS
    };

    await probe.mintAndOffer(contractOffer, { value: ETH("2") });
    expect(await collateral.ownerOf(2)).to.equal(escrow.address);
    await expectRevert(
      escrow.connect(lender).fund(1, TERMS, { value: ETH("1") }),
      "borrower cannot receive ETH"
    );
    expect((await escrow.loanInfo(1)).state).to.equal(1); // still Proposed
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
    expect(await collateral.ownerOf(2)).to.equal(escrow.address);

    await probe.configure(false, true);
    await escrow.connect(lender).fund(1, TERMS, { value: ETH("1") });
    expect((await escrow.loanInfo(1)).state).to.equal(2); // Active
    expect(await probe.callbackBlocked()).to.equal(true);
    eq(await ethers.provider.getBalance(probe.address), ETH("1"));
    await expectRevert(escrow.connect(stranger).cancelUnfunded(1, stranger.address), "not proposed");
    expect(await collateral.ownerOf(2)).to.equal(escrow.address);
  });

  it("a third party cannot withdraw the lender's or borrower's credited ETH", async function () {
    await propose(); await fund();
    await escrow.connect(borrower).repay(1, { value: ETH("0.5") });
    await expectRevert(escrow.connect(stranger).withdrawCredit(stranger.address), "no credit");
    eq(await escrow.credits(lender.address), ETH("0.5"));
    await escrow.connect(lender).withdrawCredit(stranger.address);
    eq(await escrow.credits(lender.address), ethers.constants.Zero);
    eq(await escrow.totalCredits(), ethers.constants.Zero);
  });

  it("two simultaneous borrowers cannot cross-claim each other's collateral or surplus", async function () {
    await propose(); await fund(); // token 1: borrower, 2 ETH backing, 1.1 ETH payoff

    await collateral.connect(stranger).mint({ value: ETH("3") });
    await collateral.connect(stranger).approve(escrow.address, 2);
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const second = {
      tokenId: 2, lender: lender.address, arbiter: arbiter.address,
      principal: ETH("0.5"), payoff: ETH("0.55"),
      fundingDeadline: now + 1000, term: 200, grace: 100,
      challenge: 120, arbitrateFor: 120, termsHash: TERMS
    };
    await escrow.connect(stranger).propose(second);
    await escrow.connect(lender).fund(2, TERMS, { value: ETH("0.5") });
    await escrow.connect(borrower).repay(1, { value: ETH("0.1") });
    await escrow.connect(stranger).repay(2, { value: ETH("0.2") });

    const l2 = await escrow.loanInfo(2);
    await warpAt(l2.dueAt.toNumber() + l2.grace.toNumber() + 1);
    await escrow.declareDefault(1);
    await escrow.declareDefault(2);
    const final = await escrow.loanInfo(2);
    await warpAt(final.defaultAt.toNumber() + final.challenge.toNumber() + 1);
    await escrow.liquidate(2);
    await escrow.liquidate(1);

    eq(await escrow.credits(lender.address), ETH("1.65"));
    eq(await escrow.credits(borrower.address), ETH("1.0"));
    eq(await escrow.credits(stranger.address), ETH("2.65"));
    eq(await escrow.totalCredits(), ETH("5.3"));
    eq(await ethers.provider.getBalance(escrow.address), ETH("5.3"));
    expect(await escrow.isCreditSolvent()).to.equal(true);
    await escrow.connect(borrower).withdrawCredit(borrower.address);
    eq(await escrow.credits(stranger.address), ETH("2.65"));
    eq(await escrow.totalCredits(), ETH("4.3"));
    await escrow.connect(lender).withdrawCredit(lender.address);
    await escrow.connect(stranger).withdrawCredit(stranger.address);
    eq(await escrow.totalCredits(), ethers.constants.Zero);
    eq(await ethers.provider.getBalance(escrow.address), ethers.constants.Zero);
  });

});
