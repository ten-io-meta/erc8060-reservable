const { ethers, network } = require("hardhat");
const { expect } = require("chai");
const ETH = (s) => ethers.utils.parseEther(s);
const TERMS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("buyer or floor burn; start price 3 ETH; 1-hour Dutch sale"));
const eq = (actual, expected) => expect(actual.eq(expected)).to.equal(true);

async function shouldRevert(txPromise, message) {
  let err;
  try { await txPromise; } catch(e) { err=e; }
  expect(err, "expected a revert").to.exist;
  if (message) expect(err.message).to.include(message);
}
async function at(ts) {
  await network.provider.send("evm_setNextBlockTimestamp", [ts]);
  await network.provider.send("evm_mine");
}

describe("Market-first ERC8060 collateral liquidation — lender, debtor, buyer and MEV", function () {
  let borrower, lender, buyer, arbiter, stranger, nft, loan, offer;
  beforeEach(async function () {
    [borrower, lender, buyer, arbiter, stranger] = await ethers.getSigners();
    nft = await (await ethers.getContractFactory("ERC8060NativeETHReference")).deploy();
    await nft.deployed();
    loan = await (await ethers.getContractFactory("CustodiedCollateralLoanPoC")).deploy(nft.address);
    await loan.deployed();
    await nft.connect(borrower).mint({value:ETH("2")});
    await nft.connect(borrower).approve(loan.address,1);
    const now=(await ethers.provider.getBlock("latest")).timestamp;
    offer={
      tokenId:1, lender:lender.address, arbiter:arbiter.address,
      principal:ETH("1"),payoff:ETH("1.1"),
      fundingDeadline:now+1000,term:200,grace:100,challenge:120,arbitrateFor:120,
      termsHash:TERMS,saleStartPrice:ETH("3"),saleDuration:3600
    };
  });

  async function funded() {
    await loan.connect(borrower).propose(offer);
    await loan.connect(lender).fund(1,TERMS,{value:ETH("1")});
  }
  async function defaultAndStartSale() {
    await funded();
    let info=await loan.loanInfo(1);
    await at(info.dueAt.toNumber()+info.grace.toNumber()+1);
    await loan.connect(stranger).declareDefault(1);
    info=await loan.loanInfo(1);
    await at(info.defaultAt.toNumber()+info.challenge.toNumber()+1);
    await loan.connect(stranger).startSale(1);
    return await loan.loanInfo(1);
  }

  it("borrower/lender bind the auction price and minimum ETH floor before funding",async function() {
    offer.saleStartPrice=ETH("1.99");
    await shouldRevert(loan.connect(borrower).propose(offer),"sale price below ETH floor");
    offer.saleStartPrice=ETH("3");
    offer.saleDuration=0;
    await shouldRevert(loan.connect(borrower).propose(offer),"invalid sale duration");
    offer.saleDuration=3600;
    await funded();
    const stored=await loan.loanInfo(1);
    eq(stored.saleStartPrice,ETH("3"));
    eq(stored.redemptionFloor,ETH("2"));
    eq(stored.saleDuration,ethers.BigNumber.from("3600"));
    await shouldRevert(loan.startSale(1),"not saleable");
  });

  it("purchase preserves NFT and all premium goes to borrower, with exact overbid refund",async function() {
    const info=await defaultAndStartSale();
    eq(await loan.currentSalePrice(1),ETH("3"));
    await shouldRevert(loan.burnUnsold(1),"auction still active");
    await at(info.saleStartedAt.toNumber()+1800);
    const quote=await loan.currentSalePrice(1);
    expect(quote.lt(ETH("3")) && quote.gt(ETH("2"))).to.equal(true);
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("2"),buyer.address,{value:ETH("2")}),"price above maximum");
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("3"),buyer.address,{value:ETH("2")}),"wrong bid amount");

    const receipt=await (await loan.connect(buyer).buyCollateral(
      1,ETH("3"),buyer.address,{value:ETH("3")}
    )).wait();
    const ev=receipt.events.find(e=>e.event==="NFTSold");
    const paid=ev.args.price;
    expect(paid.lt(ETH("3")) && paid.gt(ETH("2"))).to.equal(true);
    expect(await nft.ownerOf(1)).to.equal(buyer.address);
    eq(await nft.valueOf(1),ETH("2")); // NFT and market premium survive
    eq(await ethers.provider.getBalance(nft.address),ETH("2"));
    eq(await loan.credits(lender.address),ETH("1.1"));
    eq(await loan.credits(borrower.address),paid.sub(ETH("1.1")));
    eq(await loan.credits(buyer.address),ETH("3").sub(paid));
    eq(await loan.totalCredits(),ETH("3"));
    eq(await ethers.provider.getBalance(loan.address),ETH("3"));
    expect(await loan.isCreditSolvent()).to.equal(true);
    await shouldRevert(loan.burnUnsold(1),"not sale open");
    await shouldRevert(loan.connect(stranger).buyCollateral(1,ETH("3"),stranger.address,{value:ETH("3")}),"not sale open");
    await loan.connect(buyer).withdrawCredit(buyer.address);
    await loan.connect(lender).withdrawCredit(lender.address);
    await loan.connect(borrower).withdrawCredit(borrower.address);
    eq(await ethers.provider.getBalance(loan.address),ethers.constants.Zero);
  });

  it("unsold NFT cannot burn until full sale window ends; exact boundary is enforced",async function() {
    const info=await defaultAndStartSale();
    await shouldRevert(loan.connect(lender).burnUnsold(1),"auction still active");
    const end=info.saleStartedAt.toNumber()+info.saleDuration.toNumber();
    await network.provider.send("evm_setNextBlockTimestamp",[end]);
    await shouldRevert(loan.connect(stranger).burnUnsold(1),"auction still active");
    await network.provider.send("evm_setNextBlockTimestamp",[end+1]);
    await loan.connect(stranger).burnUnsold(1);
    await shouldRevert(nft.ownerOf(1),"invalid token ID");
    eq(await loan.credits(lender.address),ETH("1.1"));
    eq(await loan.credits(borrower.address),ETH("0.9"));
    eq(await ethers.provider.getBalance(loan.address),ETH("2"));
    await shouldRevert(loan.connect(stranger).burnUnsold(1),"not sale open");
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("3"),buyer.address,{value:ETH("3")}),"not sale open");
  });

  it("when onchain outstanding debt is partially repaid, sale distributes ONLY the remainder",async function() {
    await funded();
    await loan.connect(borrower).repay(1,{value:ETH("0.3")});
    let info=await loan.loanInfo(1);
    await at(info.dueAt.toNumber()+info.grace.toNumber()+1);
    await loan.declareDefault(1);
    info=await loan.loanInfo(1);
    await at(info.defaultAt.toNumber()+info.challenge.toNumber()+1);
    await loan.startSale(1);
    const receipt=await (await loan.connect(buyer).buyCollateral(
      1,ETH("3"),buyer.address,{value:ETH("3")}
    )).wait();
    const salePrice=receipt.events.find(e=>e.event==="NFTSold").args.price;
    eq(await loan.credits(lender.address),ETH("1.1")); // 0.3 + 0.8
    eq(await loan.credits(borrower.address),salePrice.sub(ETH("0.8")));
    eq(await loan.credits(buyer.address),ETH("3").sub(salePrice));
    eq(await loan.totalCredits(),ETH("3.3"));
    eq(await ethers.provider.getBalance(loan.address),ETH("3.3"));
  });

  it("full real-ETH cure during the sale returns NFT to borrower and precludes buyer/creditor burn",async function() {
    await defaultAndStartSale();
    await shouldRevert(loan.connect(stranger).settleAfterDefault(1,{value:ETH("1")}),"exact payoff required");
    await loan.connect(stranger).settleAfterDefault(1,{value:ETH("1.1")});
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("3"),buyer.address,{value:ETH("3")}),"not sale open");
    await shouldRevert(loan.burnUnsold(1),"not sale open");
    await loan.connect(borrower).claimCollateral(1,borrower.address);
    expect(await nft.ownerOf(1)).to.equal(borrower.address);
    eq(await loan.credits(lender.address),ETH("1.1"));
  });

  it("at end of auction a buyer must race to purchase before expiry; arbitrator cannot burn early",async function() {
    const info=await defaultAndStartSale();
    await shouldRevert(loan.connect(arbiter).arbitrate(1,false),"not disputed");
    await at(info.saleStartedAt.toNumber()+info.saleDuration.toNumber()+1);
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("2"),buyer.address,{value:ETH("2")}),"sale ended");
    await loan.connect(stranger).burnUnsold(1);
    eq(await loan.credits(lender.address),ETH("1.1"));
  });

  it("rejects zero or own receiver; failed sale cannot mutate credits nor NFT custody",async function() {
    await defaultAndStartSale();
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("3"),ethers.constants.AddressZero,{value:ETH("3")}),"invalid NFT receiver");
    await shouldRevert(loan.connect(buyer).buyCollateral(1,ETH("3"),loan.address,{value:ETH("3")}),"invalid NFT receiver");
    expect(await nft.ownerOf(1)).to.equal(loan.address);
    eq(await loan.totalCredits(),ethers.constants.Zero);
    eq(await ethers.provider.getBalance(loan.address),ethers.constants.Zero);
  });
});
