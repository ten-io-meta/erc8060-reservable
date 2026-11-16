const { expect } = require("chai");
const { ethers } = require("hardhat");

const ETH = ethers.constants.AddressZero;
const half = ethers.utils.parseEther("0.5");
const one = ethers.utils.parseEther("1");
const two = ethers.utils.parseEther("2");
const quarter = ethers.utils.parseEther("0.25");

async function reverts(promise, contains) {
  let error;
  try { await promise; } catch (err) { error = err; }
  expect(error, "expected transaction to revert").to.exist;
  if (contains) expect(error.message).to.include(contains);
}
function interfaceId(contract, names) {
  return ethers.utils.hexZeroPad(names.reduce(
    (acc, name) => acc.xor(ethers.BigNumber.from(contract.interface.getSighash(name))),
    ethers.BigNumber.from(0)
  ).toHexString(), 4);
}

describe("Real-ETH-backed reference candidates", function () {
  let owner, buyer, agent, stranger, strict, conditional;

  beforeEach(async function () {
    [owner, buyer, agent, stranger] = await ethers.getSigners();
    strict = await (await ethers.getContractFactory("ERC8060NativeETHReference")).deploy();
    conditional = await (await ethers.getContractFactory("ReservableConditionalETHReference")).deploy();
    await strict.deployed();
    await conditional.deployed();
  });

  describe("STRICT ERC-8060 ETH reference", function () {
    it("mints only when funded with actual ETH and reports exact redeemable value", async function () {
      await reverts(strict.mint(), "zero ETH");
      await strict.mint({ value: one });
      expect(await strict.ownerOf(1)).to.equal(owner.address);
      expect((await strict.valueOf(1)).eq(one)).to.equal(true);
      expect((await strict.totalRedeemableValue()).eq(one)).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).eq(one)).to.equal(true);
      expect(await strict.isSolvent()).to.equal(true);
      const id = interfaceId(strict, ["valueOf", "burn"]);
      expect(await strict.supportsInterface(id)).to.equal(true);
      expect(await strict.supportsInterface("0x80ac58cd")).to.equal(true);
    });

    it("only NFT owner may burn; transfer gives redemption exclusively to new owner", async function () {
      await strict.mint({ value: one });
      await strict.approve(stranger.address, 1); // ERC721 operator is still not burn-authorized
      await reverts(strict.connect(stranger).burn(1), "not NFT owner");
      await strict.transferFrom(owner.address, buyer.address, 1);
      await reverts(strict.burn(1), "not NFT owner");
      const before = await ethers.provider.getBalance(buyer.address);
      const tx = await strict.connect(buyer).burn(1);
      const receipt = await tx.wait();
      const gas = receipt.gasUsed.mul(receipt.effectiveGasPrice);
      const after = await ethers.provider.getBalance(buyer.address);
      expect(after.add(gas).sub(before).eq(one)).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).isZero()).to.equal(true);
      expect((await strict.totalRedeemableValue()).isZero()).to.equal(true);
      await reverts(strict.valueOf(1), "nonexistent token");
      await reverts(strict.connect(buyer).burn(1));
    });

    it("pools multiple real deposits without allowing double redemption or cross-token theft", async function () {
      await strict.mint({ value: one });
      await strict.connect(buyer).mint({ value: two });
      expect((await strict.totalRedeemableValue()).eq(one.add(two))).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).eq(one.add(two))).to.equal(true);
      await strict.burn(1);
      expect((await strict.valueOf(2)).eq(two)).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).eq(two)).to.equal(true);
      await strict.connect(buyer).burn(2);
      expect((await strict.totalRedeemableValue()).isZero()).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).isZero()).to.equal(true);
    });

    it("failed ETH payout restores burned-token ownership, accounting and ETH", async function () {
      const p = await (await ethers.getContractFactory("RejectETHReceiverProbe")).deploy();
      await p.deployed();
      await p.mintInto(strict.address, { value: one });
      expect(await strict.ownerOf(1)).to.equal(p.address);
      await reverts(p.attemptBurn(strict.address, 1), "ETH redemption failed");
      expect(await strict.ownerOf(1)).to.equal(p.address);
      expect((await strict.valueOf(1)).eq(one)).to.equal(true);
      expect((await strict.totalRedeemableValue()).eq(one)).to.equal(true);
      expect((await ethers.provider.getBalance(strict.address)).eq(one)).to.equal(true);
    });

    it("cannot mint or redeem a nonexistent NFT with no backing", async function () {
      await reverts(strict.valueOf(123), "nonexistent token");
      await reverts(strict.burn(123));
    });
  });

  describe("CONDITIONAL ETH-backed Reservable reference", function () {
    async function mintOne() {
      await conditional.mint({ value: one });
    }

    it("custodies ETH exactly and explicitly does not advertise strict ERC-8060", async function () {
      await reverts(conditional.mint(), "zero ETH");
      await mintOne();
      const strictId = interfaceId(strict, ["valueOf", "burn"]);
      const reserveId = interfaceId(conditional, [
        "approveReserve", "reserveValue", "releaseValue",
        "reserveAllowance", "lockedValue", "availableValue"
      ]);
      expect(await conditional.supportsInterface(strictId)).to.equal(false);
      expect(await conditional.supportsInterface(reserveId)).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).eq(one)).to.equal(true);
      expect((await conditional.totalBacked()).eq(one)).to.equal(true);
      expect((await conditional.backingOf(1)).eq(one)).to.equal(true);
      expect(await conditional.isSolvent()).to.equal(true);
      await reverts(conditional.availableValue(1, buyer.address), "ETH only");
    });

    it("real withdrawals may never consume an active spender lock", async function () {
      await mintOne();
      await conditional.approveReserve(1, agent.address, ETH, half);
      await conditional.connect(agent).reserveValue(1, ETH, half);
      await reverts(conditional.withdrawAvailable(1, one), "insufficient available");
      await conditional.withdrawAvailable(1, half);
      expect((await conditional.totalBacked()).eq(half)).to.equal(true);
      expect((await conditional.lockedValue(1, ETH)).eq(half)).to.equal(true);
      expect((await conditional.availableValue(1, ETH)).isZero()).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).eq(half)).to.equal(true);
      await reverts(conditional.redeemWhenUnlocked(1), "active reservation blocks redemption");
      await conditional.connect(agent).releaseValue(1, ETH, half);
      await conditional.redeemWhenUnlocked(1);
      expect((await conditional.totalBacked()).isZero()).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
      await reverts(conditional.redeemWhenUnlocked(1));
    });

    it("preserves active locks through ERC721 transfer but cancels old reserve allowance", async function () {
      await mintOne();
      await conditional.approveReserve(1, agent.address, ETH, one);
      await conditional.connect(agent).reserveValue(1, ETH, quarter);
      await conditional.transferFrom(owner.address, buyer.address, 1);
      expect((await conditional.lockedValue(1, ETH)).eq(quarter)).to.equal(true);
      expect((await conditional.availableValue(1, ETH)).eq(one.sub(quarter))).to.equal(true);
      expect((await conditional.reserveAllowance(1, agent.address, ETH)).isZero()).to.equal(true);
      await reverts(conditional.connect(agent).reserveValue(1, ETH, quarter), "insufficient reserve allowance");
      await reverts(conditional.withdrawAvailable(1, quarter), "not NFT owner");
      await conditional.connect(buyer).approveReserve(1, agent.address, ETH, half);
      expect((await conditional.reserveAllowance(1, agent.address, ETH)).eq(quarter)).to.equal(true);
      await conditional.connect(agent).releaseValue(1, ETH, quarter);
      expect((await conditional.availableValue(1, ETH)).eq(one)).to.equal(true);
      await conditional.connect(buyer).redeemWhenUnlocked(1);
      expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
    });

    it("revocation preserves committed locks and other spenders cannot release them", async function () {
      await mintOne();
      await conditional.approveReserve(1, agent.address, ETH, half);
      await conditional.connect(agent).reserveValue(1, ETH, half);
      await conditional.approveReserve(1, agent.address, ETH, 0);
      expect((await conditional.lockedValue(1, ETH)).eq(half)).to.equal(true);
      expect((await conditional.reserveAllowance(1, agent.address, ETH)).isZero()).to.equal(true);
      await reverts(conditional.connect(stranger).releaseValue(1, ETH, quarter), "release exceeds allocation");
      await reverts(conditional.connect(agent).reserveValue(1, ETH, 1), "insufficient reserve allowance");
      await conditional.connect(agent).releaseValue(1, ETH, half);
      await reverts(conditional.connect(agent).releaseValue(1, ETH, 1), "release exceeds allocation");
    });

    it("new deposits are real ETH and only increase the selected NFT liability", async function () {
      await mintOne();
      await conditional.connect(buyer).mint({ value: two });
      await reverts(conditional.connect(stranger).deposit(1, { value: one }), "not NFT owner");
      await reverts(conditional.deposit(1), "zero ETH");
      await conditional.deposit(1, { value: half });
      expect((await conditional.backingOf(1)).eq(one.add(half))).to.equal(true);
      expect((await conditional.backingOf(2)).eq(two)).to.equal(true);
      expect((await conditional.totalBacked()).eq(one.add(half).add(two))).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).eq(one.add(half).add(two))).to.equal(true);
      await conditional.connect(buyer).redeemWhenUnlocked(2);
      expect((await ethers.provider.getBalance(conditional.address)).eq(one.add(half))).to.equal(true);
    });

    it("zero address and unsupported assets cannot be used to create or disguise locks", async function () {
      await mintOne();
      await reverts(conditional.transferFrom(owner.address, ETH, 1));
      await reverts(conditional.approveReserve(1, ETH, ETH, 1), "invalid spender");
      await reverts(conditional.approveReserve(1, agent.address, buyer.address, 1), "ETH only");
      await reverts(conditional.connect(agent).reserveValue(1, buyer.address, 1), "ETH only");
      await reverts(conditional.connect(agent).releaseValue(1, buyer.address, 1), "ETH only");
      await reverts(conditional.connect(agent).reserveValue(1, ETH, 0), "zero amount");
    });

    it("matches per-token custody liabilities over many deposits, locks and withdrawals", async function () {
      await mintOne();
      await conditional.connect(buyer).mint({ value: two });
      let b1 = one;
      let b2 = two;
      let l1 = ethers.BigNumber.from(0);
      let l2 = ethers.BigNumber.from(0);
      await conditional.approveReserve(1, agent.address, ETH, one);
      await conditional.connect(buyer).approveReserve(2, agent.address, ETH, two);
      for (let i = 0; i < 20; i++) {
        if (i % 4 === 0) {
          await conditional.connect(agent).reserveValue(1, ETH, quarter);
          l1 = l1.add(quarter);
        } else if (i % 4 === 1) {
          await conditional.connect(agent).reserveValue(2, ETH, quarter);
          l2 = l2.add(quarter);
        } else if (i % 4 === 2) {
          await conditional.connect(agent).releaseValue(1, ETH, quarter);
          l1 = l1.sub(quarter);
        } else {
          await conditional.connect(agent).releaseValue(2, ETH, quarter);
          l2 = l2.sub(quarter);
        }
        const total = b1.add(b2);
        expect((await conditional.totalBacked()).eq(total)).to.equal(true);
        expect((await ethers.provider.getBalance(conditional.address)).eq(total)).to.equal(true);
        expect((await conditional.backingOf(1)).eq(b1)).to.equal(true);
        expect((await conditional.backingOf(2)).eq(b2)).to.equal(true);
        expect((await conditional.lockedValue(1, ETH)).eq(l1)).to.equal(true);
        expect((await conditional.lockedValue(2, ETH)).eq(l2)).to.equal(true);
        expect((await conditional.availableValue(1, ETH)).eq(b1.sub(l1))).to.equal(true);
        expect((await conditional.availableValue(2, ETH)).eq(b2.sub(l2))).to.equal(true);
      }
      await conditional.withdrawAvailable(1, half);
      b1 = b1.sub(half);
      expect((await conditional.totalBacked()).eq(b1.add(b2))).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).eq(b1.add(b2))).to.equal(true);
      await conditional.redeemWhenUnlocked(1);
      await conditional.connect(buyer).redeemWhenUnlocked(2);
      expect((await conditional.totalBacked()).isZero()).to.equal(true);
      expect((await ethers.provider.getBalance(conditional.address)).isZero()).to.equal(true);
    });
  });
});
