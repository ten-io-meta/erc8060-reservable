# Market-first ETH-backed NFT collateral — experimental auction design

**Status:** Research prototype. Not independently audited and NOT suitable for real custody. This branch does not modify the six-function `IERC8060Reservable`, public ERC-8060 drafts, `main`, or TEN.IO Mainnet deployments.

## Why this is necessary

The previous `CustodiedCollateralLoanPoC` always burned a defaulted strict ERC-8060-backed NFT. Burning captures its ETH redemption floor but permanently destroys potential cultural/secondary market value above that floor. It is not valid to claim that the ETH floor represents the fair market value of the NFT.

The new model attempts **real onchain price discovery FIRST**, and burns only if the agreed period produces no sale. There is no external oracle, price feed, DEX or administrative appraisal.

## Fixed terms and consent

Borrower proposes the escrow loan with immutable `Offer.saleStartPrice` (ETH wei) and `Offer.saleDuration` (1 hour to 30 days). The lender inspects and accepts the same terms when funding exact principal. On proposal, `redemptionFloor = valueNft.valueOf(tokenId)` is recorded and requires:

```
startPrice >= redemptionFloor >= totalPayoff >= remainingDebt
```

The floor is rechecked at funding, auction start, purchase, and burn. This is a **strict, reviewed native-ETH NFT assumption**; a malicious or upgradeable collection can still make the system fail, and no `valueOf` declaration alone certifies the true backing.

## State transitions

```text
Proposed -> Active -> Repaid -> NFTReturned
                |
                -> Defaulted -> (challenge, optional Disputed + arbiter period)
                                   |
                                   v
                             SaleOpen (Dutch price)
                             /             \
                        Buyer pays         No buyer until end
                            |                    |
                           Sold               Liquidated
                     NFT transferred         NFT burned
                     ETH sale proceeds       ETH redemption floor
```

The borrower may settle the **entire remaining debt with real ETH**, or the actual lender may voluntarily waive it, before any sale or burn. After a sale/burn commits, both actions revert. A noncooperating arbiter cannot hold the NFT indefinitely because anyone may start the auction after its previously agreed period. An arbitrator upholding default **after the challenge period** only starts the auction, never burns immediately.

**No sale or burn is automatic:** a third party must submit transactions to start the auction, buy, or burn after expiry.

## Auction and price

Time-based descending-price ("Dutch") offer:

```text
P(t) = startingPrice - floor((startingPrice - floorValue) * elapsed / duration)
```

While the window is open `0 <= elapsed <= duration`, buyers can pay `maxPrice` in ETH with `price <= maxPrice`. Prices can move between transaction preparation and inclusion: the maxPrice acts as slippage protection. Any difference between their actual maximum and the execution price is a **withdrawable credit assigned to that same buyer**; it is never retained by the seller or lender.

The sale function:

1. Validates the accepted sale state, deadline, NFT custodian and immutable ETH floor.
2. Atomically sets `Sold`, credits parties based on ETH actually paid, and safely transfers the *unburned* NFT to the buyer's nominated nonzero receiver (not the escrow itself).
3. Checks the NFT's new owner matches that receiver. A rejected transfer reverts the complete ETH movement/credit allocation.
4. Prevents a second sale or subsequent burn of that NFT.

If there is no buyer after the deadline, anyone calls `burnUnsold()`. It verifies the true ETH balance delta from the NFT's `burn()`, credits the lender only the unpaid payoff, gives the borrower the remainder, and destroys the token as the **last-resort** fallback.

## Economic invariant: one ETH waterfall

Let:
- `R` = ETH repaid and recorded before default.
- `D` = fixed original payoff.
- `O = D - R` = unpaid debt at sale/burn.
- `P` = actual NFT sale execution price (or `F` = ETH returned by verified fallback burn).
- `B` = buyer maximum bid `>= P`.

**Sale case:**
```
lender allocation = R + O = D
borrower surplus = P - O
buyer refund      = B - P
total recorded credits increase = B
actual received ETH = B
previous repayment ETH = R
escrow ETH == R + B == total outstanding credits (before withdrawal)
```

**Burn fallback:**
```
lender allocation = R + O = D
borrower surplus = F - O
new escrow ETH = F
escrow ETH == R + F == total outstanding credits (before withdrawal)
```

The code checks `P >= F >= D` and that the total outstanding is covered. Funds are received in the escrow; no claim is created from a purely accounting reservation. Withdrawals use pull payments and are nonreentrant. It is possible for some credits to have been withdrawn before the sale/burn; the global invariant then compares **current outstanding credits** to actual balance, not aggregate historic allocations.

## Realistic example

NFT's embedded ETH floor = **2 ETH**; buyer values it above that floor. Lender principal = **1 ETH**, agreed payoff = **1.1 ETH**. Borrower has already paid **0.3 ETH**, leaving **0.8 ETH** owed.

If a buyer pays **2.5 ETH**, then:
- Lender receives **0.8 ETH** in additional recoveries (total payout due 1.1 ETH including 0.3 earlier).
- Borrower receives **1.7 ETH** of the NFT sale proceeds.
- NFT passes intact to the buyer, with its embedded 2 ETH still redeemable.

If no buyer appears, burning returns the 2 ETH floor:
- Lender receives additional **0.8 ETH**.
- Borrower receives **1.2 ETH**.
- NFT is destroyed. That is the irreversible loss this design tries to avoid.

## Threats still unresolved

- This is NOT a best-price guaranteed marketplace. A Dutch auction can fail to attract bids, and sophisticated buyers may time purchases. Bot/MEV front-running can determine the winning buyer. There is no anti-sybil auction, demand guarantee, NFT discovery/listing, oracle, fair market appraisal, cancellation of a prior executed sale or offchain legal claim.
- Fixed sale parameters are **not modifiable later**; this prevents unilateral repricing, but may misprice assets when the market changes.
- `block.timestamp` impacts execution price; `maxPrice` avoids overpaying above an explicit buyer ceiling but cannot guarantee an NFT purchase.
- The borrower can repay fully during `SaleOpen`; a valid purchase or repayment transaction that executes first wins. This atomic ordering is not a resolution of external disputes.
- NFT strict redeemability, bytecode provenance, code immutability and underlying ETH solvency still require independent review. A malicious ERC721 could lie, break transfers or block redemptions.
- A sale or burn after expiry depends on someone sending a transaction; no keeper incentive is provided. At expiry there is a strict boundary: sale allowed through `end`, burn permitted only **after** `end`.
- Nobody can promise premium exists, that the NFT will sell, or that the borrowing terms are fair. No buyer in the fixed period means original ETH-floor burn remains possible.
- No arbitration of cash/bank-transfer proofs: debtor and creditor must settle real ETH or use actual lender-only waiver. A hash/bond alone does not establish a payment.
- The buyer may use a contract that cannot receive ERC721; such a bid reverts atomically and cannot divert lender's credits.
- To satisfy Ethereum EIP-170 bytecode constraints, both Hardhat and Foundry compile with the same standard optimizer settings (200 runs), and Hardhat tests explicitly require `deployedBytecode.length <= 24,576`. This is a deployability gate, not a safety certificate.

## Tests

- `test/market-first-collateral-sale.js`: explicit premium sale and ERC721 custody, underbidding, refund, slippage, exact expiry boundary, borrower cure, default accounting with partial repayments, and invalid recipients.
- `test-foundry/MarketFirstCollateralSale.t.sol`: adversarial price and repayments fuzzing, sale after challenge, correct debt waterfall, overbid refund, failing ERC721 receiver, and mandatory burn delay.
- Existing `test/custodied-collateral-loan.js` and `test-foundry/CustodiedCollateralLoan.t.sol`: upgraded to the forced auction-before-burn path. No direct owner/lender/arbiter burning shortcut.
- `test/eth-contract-size.js`: EIP-170 runtime-size limit.

**Passing tests cannot replace an independent audit.**
