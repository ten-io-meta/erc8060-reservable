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
| Disputed | Either party can challenge within finite window | NFT held; authorized arbiter may rule within finite period |
| Forgiven | Named arbiter confirms offchain satisfaction or forgiveness | NFT can be returned; previously recorded lender credits stay intact |
| Liquidated | After challenge expiry or by arbiter, or after arbiter timeout | NFT burned; exact ETH received verified; lender gets **only unpaid payoff**, borrower the remaining ETH |
| NFTReturned / Cancelled | Terminal | No second collateral return or second liquidation |

**Default financial example:** NFT redemption floor 2.0 ETH, lender principal 1.0 ETH, fixed agreed payoff 1.1 ETH, 0.3 ETH repaid before default. Burning returns 2.0 ETH. Lender receives **0.8 ETH more** on liquidation (total 1.1 ETH with earlier 0.3), borrower receives 1.2 ETH surplus. Funds remain as pull credits until each party withdraws, preventing a malicious ETH receiver from vetoing liquidation.

## Deliberate trade-offs / unresolved questions

1. **Pre-agreed trusted arbitration.** The named arbiter can forgive remaining debt without an onchain ETH payment and permit the borrower to recover the NFT. That can disadvantage a lender if the arbiter lies or colludes; there is no trustless way to establish disputed offchain repayment. The parties must agree to that trust model up front. If the arbiter is unresponsive, the immutable fallback is **default liquidation**, not debt forgiveness.
2. **No fair market sale.** Burning the NFT eliminates secondary market value above its native ETH floor. A more sophisticated lending product may require an auction, reserve prices, oracle or alternative sale mechanism and further borrower protections. This prototype deliberately implements *only* deterministic ETH redemption with a fixed payoff.
3. **No legal enforceability or outside asset verification.** This code recognizes actual ETH transactions inside the application, not cash, bank transfers, courts or offchain delivery. `termsHash` commits to bytes but does not validate their meaning.
4. **Deadline and automation.** Default, arbitration and liquidation are permissionless calls where stated but do not occur automatically; someone must submit a transaction. Timestamp boundaries have the usual execution-block sequencing limits.
5. **Underlying collection trust.** Accept only the specific strict reference NFT code reviewed and deployed by a trusted operator. `supportsInterface` or `valueOf` cannot prove solvency on their own. If a token misreports payout, the checked burn reverts without assigning false credits. Upgrades to the NFT would require additional scrutiny.
6. **Recovery limits.** A user who loses their borrower key may be unable to cancel or reclaim, even though debt resolution can proceed permissionlessly. The design cannot guarantee recovery against lost keys and simultaneously forbid other parties from taking their NFT; pre-agreed contract-wallet recovery or signature delegation would be separate audited mechanisms.
7. **Rescue of unexpected donations.** Extra ETH deliberately forced into the escrow remains uncredited. There is no admin withdrawal, so unsolicited ETH may become stranded. This avoids allowing operators to skim pledged/credited money at the cost of recoverability.
8. **No general fairness guarantee from tests.** A real-world loan product needs threat modeling, independent audit, deployment code attestation and policy review. This proof of concept is not suitable for production custody.

## Tests

- `test/custodied-collateral-loan.js`: funding, debt ledger, partial and full payments, unauthorized acts, reclaim, onchain default, challenge, arbitration, timeout and pull-credit behavior.
- `test-foundry/CustodiedCollateralLoan.t.sol`: varied amounts, partial payments and exact ETH balance invariants for loan liquidation and repayment.

For running against local EVMs only: `npm test` and `forge test --match-path 'test-foundry/*.t.sol' -vv`. No Mainnet RPC or private keys are needed.
