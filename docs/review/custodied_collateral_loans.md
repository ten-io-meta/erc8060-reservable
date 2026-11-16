# Custodied collateral loan — experimental economic reference

**Security status:** research prototype only. No external audit. **Do not deploy with real assets.** The original `IERC8060Reservable` six-function ABI is unchanged.

## Why this contract is separate from Reservable

A spender's `reserveValue` lock is **not ETH custody in favor of a creditor**: no `claim`, `payout` or `liquidate` operation exists within those six methods. Releasing a reservation on its deadline does not settle a debt. We therefore implement a **different, explicitly custodial application** that takes the actual NFT and holds the right to redeem it. This prototype is compatible with the strict `ERC8060NativeETHReference`, which redeems backing immediately on `burn(tokenId)` and has no active reservation semantics.

A **nonstandard reservation-conditioned token cannot be used interchangeably**, because locks would block immediate burn. The deployed code and ETH backing of the exact chosen NFT contract must be reviewed; the immutable constructor parameter does not independently validate a malicious NFT implementation.

## Fixed terms and explicit consent

Before lender funding, the borrower proposes and escrows the NFT onchain. Terms include: the exact collateral NFT and collection, named lender, borrower, named arbiter, exact ETH principal, fixed total payoff, time to maturity, grace window, default-challenge window, arbitration timeout and a `termsHash`. The contract requires `valueOf(tokenId) >= payoff` at proposal AND funding. The borrower thereby accepts that the NFT **will be destroyed and only its native ETH backing redeemed** if the agreed default conditions are reached, even if its external trading or artistic value is much greater.

The lender agrees to precisely the stored offer by calling `fund(loanId, expectedTermsHash)` with **exactly** the required principal in ETH. The contract atomically forwards the ETH to the borrower and begins the loan. If the payment cannot be delivered the funding transaction reverts in full; there is no phantom onchain-funded loan.

## Financial state transitions

| State | Legitimate action | Actual ETH movement |
|---|---|---|
| Proposed | Borrower can cancel; only matching named lender can fund | NFT held by loan contract; lender not yet out of pocket |
| Active | Anyone can pay toward exact fixed payoff until end of grace | Real ETH collected, and equal creditor pull-credit recorded |
| Repaid | Borrower can reclaim NFT to chosen address | Original NFT returned; lender may withdraw credits |
| Defaulted | Anyone can mark overdue loan after grace | NFT still custodied; no automatic release to debtor |
| Disputed | Either party can challenge within finite window | NFT held; anyone can settle the full outstanding amount with real ETH; arbiter may fund full settlement or uphold default after challenge |
| Forgiven | **Only the named lender** voluntarily waives unpaid debt | NFT can be returned; existing lender credits remain withdrawable |
| SaleOpen | After challenge expiry or arbitration timeout, or by arbiter after challenge | NFT offered in pre-agreed Dutch auction; floor is the embedded ETH backing |
| Sold | Buyer pays true ETH market price (at or above backing) | NFT transferred intact; lender gets only unpaid payoff, borrower gets surplus, buyer gets bid refund |
| Liquidated | ONLY after agreed auction has ended unsold | NFT burned; exact ETH backing verified; lender gets only unpaid payoff, borrower remainder |
| NFTReturned / Cancelled | Terminal | No second collateral return or second liquidation |

**Default financial example:** NFT redemption floor 2 ETH; fixed loan payoff 1.1 ETH; 0.3 ETH already repaid. A successful Dutch-auction sale for 2.5 ETH pays the lender 0.8 ETH more, returns **1.7 ETH** to borrower, and transfers the NFT intact to the buyer. If no one buys before the agreed auction ends, verified burn yields 2 ETH; the lender still gets 0.8 ETH and the borrower **1.2 ETH**. All awards remain withdrawable pull credits.

## Deliberate trade-offs / unresolved questions

1. **Arbitration without unsecured forgiveness.** The named arbiter is no longer allowed to forgive a lender's outstanding claim without payment. In a dispute, it can settle only by depositing the **exact unpaid ETH**, which becomes the lender's credit, or uphold default for collateral liquidation **after the challenge period**. Only the actual lender can call `lenderWaive` to voluntarily acknowledge offchain payment/forgive their remaining claim. Anyone can cure `Defaulted` or `Disputed` by paying the full remaining ETH onchain before liquidation. If the arbiter disappears, the immutable fallback remains default liquidation after the dispute timeout. A compromised lender account can still waive its own claim; a compromised arbiter can still accelerate liquidation after challenge expiry. No mechanism can truthlessly establish an offchain payment without outside evidence and a trust rule.
2. **Market premium is NOT guaranteed.** A buyer may purchase the NFT through a time-limited Dutch auction at a pre-agreed starting price declining to its native ETH floor. This **attempts** to preserve sale premium, but is not an oracle, fair-value guarantee, competitive English auction or liquid marketplace. Without a buyer, the NFT is still burned after auction expiration. The exact formula, time boundaries, proceeds and risks are in [market-first liquidation](market_first_collateral_liquidation.md).
3. **No legal enforceability or outside asset verification.** This code recognizes actual ETH transactions inside the application, not cash, bank transfers, courts or offchain delivery. `termsHash` commits to bytes but does not validate their meaning.
4. **Deadline and automation.** Default declaration, sale opening, purchase and fallback burn require separate onchain transactions; none occurs automatically. An arbiter upholding default after challenge now **starts the auction**, not a direct burn. Full debt cure or lender waiver is allowed while the sale is open but not after a successful purchase or burn. Price and execution ordering face block-timestamp and MEV competition, with buyer slippage capped by `maxPrice`.
5. **Underlying collection trust.** Accept only the specific strict reference NFT code reviewed and deployed by a trusted operator. `supportsInterface` or `valueOf` cannot prove solvency on their own. If a token misreports payout, the checked burn reverts without assigning false credits. Upgrades to the NFT would require additional scrutiny.
6. **Recovery limits.** A user who loses their borrower key may be unable to cancel or reclaim, even though debt resolution can proceed permissionlessly. The design cannot guarantee recovery against lost keys and simultaneously forbid other parties from taking their NFT; pre-agreed contract-wallet recovery or signature delegation would be separate audited mechanisms.
7. **Rescue of unexpected donations.** Extra ETH deliberately forced into the escrow remains uncredited. There is no admin withdrawal, so unsolicited ETH may become stranded. This avoids allowing operators to skim pledged/credited money at the cost of recoverability.
8. **No general fairness guarantee from tests.** A real-world loan product needs threat modeling, independent audit, deployment code attestation and policy review. This proof of concept is not suitable for production custody.

## Tests

- `test/custodied-collateral-loan.js`: funding, debt ledger, partial and full payments, unauthorized acts, reclaim, onchain default, challenge, funded arbitration, creditor-only waiver, default cure, timeout and pull-credit behavior.
- `test-foundry/CustodiedCollateralLoan.t.sol`: varied amounts, partial payments, creditor-only waivers, fully ETH-funded dispute settlement, default cures and exact ETH balance invariants.

For running against local EVMs only: `npm test` and `forge test --match-path 'test-foundry/*.t.sol' -vv`. No Mainnet RPC or private keys are needed.

## Security correction after external adversarial review — November 2026

The prior prototype permitted `arbiter.arbitrate(loanId, true)` to forgive an unpaid onchain debt at **zero ETH**. This was an explicit trust shortcut, but it allowed a compromised or colluding arbiter to deprive the lender of remaining payoff while releasing the NFT. The external review identified this as the primary high-severity economic risk.

This version removes **unilateral, unpaid arbiter forgiveness**. Its settlement and waiver pathways are distinct:

- `arbitrate(id, true)` requires `msg.value == payoff - repaid`, credits that exact ETH to the lender, and marks the loan fully paid. Arbiter cannot access NFT or creditor credits. `arbitrate(id, false)` **opens the bounded auction** with no payment supplied and only after the agreed challenge window. It cannot immediately burn collateral.
- `settleAfterDefault(id)` requires the exact same outstanding ETH and can be funded by any address before a successful liquidation (no duplicate recovery).
- `lenderWaive(id)` is an express decision **signed as a transaction by the actual named lender**, who alone can voluntarily release its unpaid rights; an arbiter or borrower cannot impersonate this authorization.
- The code does not try to infer settlement from a hash, an unchallenged assertion, or a posted bond. Such mechanisms are not proof of offchain payment without objective verification and an explicit trust model.

**Remaining economic limitation:** sale-first auction cannot guarantee discovery of a willing buyer or a fair market price, even though it avoids immediate destruction where a buyer does appear. The alternative ETH-floor burn still destroys any remaining market premium after the contractually agreed sale window expires. The exact collateral bytecode and backing accounting must be reviewed independently because `valueOf` alone cannot certify solvency.

No independent professional security audit has been conducted. This change is a research correction, not evidence of production readiness.
