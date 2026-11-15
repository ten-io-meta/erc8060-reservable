const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("ERC8060 - default sale without confiscating backing", function () {
  const ETH = ethers.utils.parseEther("1");
  const DEBT = ethers.utils.parseEther("0.3");
  const SURPLUS = ETH.sub(DEBT);
  const DURATION = 3600;
  const TOKEN = 1;

  let borrower, lender, buyer, stranger;
  let nft, vault, fundingExpiry;

  async function fails(promise) {
    let failed = false;
    try {
      await promise;
    } catch (e) {
      failed = true;
    }
    expect(failed).to.equal(true);
  }

  beforeEach(async function () {
    [borrower, lender, buyer, stranger] = await ethers.getSigners();

    nft = await (await ethers.getContractFactory(
      "ERC8060BackedNFTLab"
    )).deploy();
    await nft.deployed();
    await nft.mint({ value: ETH });

    vault = await (await ethers.getContractFactory(
      "ERC8060DefaultSaleLab"
    )).deploy(nft.address);
    await vault.deployed();

    await nft.approve(vault.address, TOKEN);

    fundingExpiry = (
      await ethers.provider.getBlock("latest")
    ).timestamp + 600;
  });

  async function open() {
    await vault.openLoan(
      TOKEN, lender.address, DEBT, ETH, fundingExpiry, DURATION
    );
  }

  async function fund() {
    await vault.connect(lender).fundLoan(0, { value: DEBT });
  }

  async function overdue() {
    await network.provider.send(
      "evm_increaseTime", [DURATION + 2]
    );
    await network.provider.send("evm_mine");
  }

  it("strict ERC8060 supports ERC165 and full burn redemption", async function () {
    const iface = new ethers.utils.Interface([
      "function valueOf(uint256) view returns (uint256)",
      "function burn(uint256)"
    ]);
    let id = ethers.BigNumber.from(0);

    for (const signature of Object.keys(iface.functions)) {
      id = id.xor(
        ethers.BigNumber.from(iface.getSighash(signature))
      );
    }

    expect(
      await nft.supportsInterface(
        ethers.utils.hexZeroPad(id.toHexString(), 4)
      )
    ).to.equal(true);

    expect(
      (await nft["valueOf(uint256)"](TOKEN)).eq(ETH)
    ).to.equal(true);

    await nft.burn(TOKEN);

    expect(
      (await ethers.provider.getBalance(nft.address)).isZero()
    ).to.equal(true);
  });

  it("vault holds NFT without touching backing", async function () {
    await open();

    expect(await nft.ownerOf(TOKEN)).to.equal(vault.address);
    expect(
      (await nft["valueOf(uint256)"](TOKEN)).eq(ETH)
    ).to.equal(true);
    expect(
      (await ethers.provider.getBalance(nft.address)).eq(ETH)
    ).to.equal(true);
  });

  it("rejects outsider or incorrect funding", async function () {
    await open();

    await fails(
      vault.connect(stranger).fundLoan(0, { value: DEBT })
    );
    await fails(
      vault.connect(lender).fundLoan(0, { value: ETH })
    );
  });

  it("borrower receives funds and recovers NFT after repayment", async function () {
    await open();

    const before = await ethers.provider.getBalance(borrower.address);
    await fund();
    const after = await ethers.provider.getBalance(borrower.address);

    expect(after.sub(before).eq(DEBT)).to.equal(true);

    await vault.repayLoan(0, { value: DEBT });

    expect(await nft.ownerOf(TOKEN)).to.equal(borrower.address);
    expect(
      (await vault.credits(lender.address)).eq(DEBT)
    ).to.equal(true);

    await fails(vault.repayLoan(0, { value: DEBT }));
  });

  it("cannot liquidate before loan maturity", async function () {
    await open();
    await fund();

    await fails(
      vault.connect(buyer).buyDefaultedNFT(
        0, ETH, { value: ETH }
      )
    );
  });

  it("late funding still grants full repayment duration", async function () {
    await open();

    await network.provider.send("evm_increaseTime", [595]);
    await network.provider.send("evm_mine");

    await fund();

    const loan = await vault.loans(0);
    const block = await ethers.provider.getBlock("latest");

    expect(
      loan.repayDeadline.toNumber() - block.timestamp
    ).to.equal(DURATION);
  });

  it("default sale pays lender and returns surplus", async function () {
    await open();
    await fund();
    await overdue();

    await vault.connect(buyer).buyDefaultedNFT(
      0, ETH, { value: ETH }
    );

    expect(await nft.ownerOf(TOKEN)).to.equal(buyer.address);

    expect(
      (await vault.credits(lender.address)).eq(DEBT)
    ).to.equal(true);

    expect(
      (await vault.credits(borrower.address)).eq(SURPLUS)
    ).to.equal(true);

    expect(
      (await nft["valueOf(uint256)"](TOKEN)).eq(ETH)
    ).to.equal(true);

    await nft.connect(buyer).burn(TOKEN);

    expect(
      (await ethers.provider.getBalance(nft.address)).isZero()
    ).to.equal(true);
  });

  it("cannot take collateral for free or below agreed price", async function () {
    await open();
    await fund();
    await overdue();

    await fails(
      vault.connect(stranger).buyDefaultedNFT(
        0, ETH, { value: DEBT }
      )
    );

    expect(await nft.ownerOf(TOKEN)).to.equal(vault.address);
  });

  it("buyer can enforce minimum backing", async function () {
    await open();
    await fund();
    await overdue();

    await fails(
      vault.connect(buyer).buyDefaultedNFT(
        0, ETH.add(1), { value: ETH }
      )
    );

    expect(await nft.ownerOf(TOKEN)).to.equal(vault.address);
  });

  it("borrower may cancel unfunded loan", async function () {
    await open();

    await fails(vault.connect(stranger).cancelUnfunded(0));

    await vault.cancelUnfunded(0);

    expect(await nft.ownerOf(TOKEN)).to.equal(borrower.address);
  });

  it("expired unfunded loan can be cancelled by anyone", async function () {
    await open();

    await network.provider.send("evm_increaseTime", [601]);
    await network.provider.send("evm_mine");

    await vault.connect(stranger).cancelUnfunded(0);

    expect(await nft.ownerOf(TOKEN)).to.equal(borrower.address);

    await fails(
      vault.connect(lender).fundLoan(0, { value: DEBT })
    );
  });

  it("funded loan cannot be cancelled or sold twice", async function () {
    await open();
    await fund();

    await fails(vault.cancelUnfunded(0));

    await overdue();

    await vault.connect(buyer).buyDefaultedNFT(
      0, ETH, { value: ETH }
    );

    await fails(
      vault.connect(stranger).buyDefaultedNFT(
        0, ETH, { value: ETH }
      )
    );
  });

  it("lender and borrower withdraw sale proceeds", async function () {
    await open();
    await fund();
    await overdue();

    await vault.connect(buyer).buyDefaultedNFT(
      0, ETH, { value: ETH }
    );

    await vault.connect(lender).withdrawCredit();
    await vault.withdrawCredit();

    expect(
      (await ethers.provider.getBalance(vault.address)).isZero()
    ).to.equal(true);
  });
});