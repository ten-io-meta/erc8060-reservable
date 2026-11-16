# Bilateral, time-bounded reservations — application-layer reference

**Status:** Experimental design and proof-of-concept. Not externally audited and not suitable for funds without further review.

## Problem

The six-function `IERC8060Reservable` interface has no privileged `forceRelease()`, and a spender's locked amount persists across NFT transfers. If the spender loses its keys or becomes uncooperative, a direct reservation can remain locked forever. Granting the NFT owner unilateral release would defeat a valid third party's protected allocation.

**Important boundary:** `IERC8060Reservable` is accounting and authorization, NOT payment or debt enforcement. A timeout is safe only where **both parties explicitly agreed that the reservation ends at that time**. An overdue loan or unresolved claim cannot silently be erased by pretending that this lock is a payment.

## Reference solution: `BilateralTimeboundReserve`

The separate application contract is the authorized reservation spender; it uses the original unchanged `IERC8060Reservable` ABI and tracks immutable `tokenId`, amount, beneficiary, proposer, ETH asset, `deadline` and `termsHash`.

1. **Propose**: current NFT owner offers fixed terms, a nonzero beneficiary, an ETH amount and a hard expiry no more than 365 days out. No lock yet.
2. **Approve**: NFT owner grants this exact application spender enough reserve allowance on the NFT. This is **only** authorization; no funds are yet locked.
3. **Accept**: the named beneficiary independently accepts the terms hash onchain, while the original proposer still owns the NFT, the expiry has not passed and reserve allowance is available. The contract immediately calls `reserveValue()` as the spender. The offer is now an active commitment.
4. **Before expiry**: the NFT owner cannot cancel, revoke, withdraw or redeem the accepted locked amount. A transfer preserves the lock. Only the designated beneficiary can voluntarily release early.
5. **At or after the accepted expiry**: **anyone** can call `releaseExpired()`. This invokes the correct spender's `releaseValue()`, making the protected amount *available to the current NFT owner*, not transferring or paying it to the beneficiary.
6. **No extension by one party**: stored expiry, amount and beneficiary are immutable. A new period requires a new mutually accepted agreement and sufficient unreserved backing.

Pre-acceptance proposals can be cancelled by the proposer or rejected by the beneficiary because nothing has been locked. The fixed bounded expiry avoids an accidental infinite commitment. `ReentrancyGuard` and checks-effects-interactions are used around external contract calls.

### Why this does NOT solve every commercial escrow

This model is appropriate for a **time-limited lock / availability commitment** in which expiry constitutes the parties' mutually accepted release condition. It does not check delivery, court orders, payment, default, loan maturity, satisfaction of debt, third-party attestations, or beneficiary entitlement. **There is no settlement or transfer to the beneficiary**. The token owner can withdraw any portion that was never reserved, and may withdraw the previously locked portion only after the agreed expiry or voluntary beneficiary release.

For a collateralized loan or purchase whose claim remains outstanding beyond an expiry, a different agreement contract must implement the actual payoff/claim/dispute rules (or an independently trusted adjudication mechanism) BEFORE it is safe to permit automatic expiry. The six-function core cannot itself consummate the payment.

### Operational caveats

- `releaseExpired()` is **permissionless, not automatic**. Someone must submit a transaction and pay gas; no administrator/cron private key is needed, and neither party can prevent execution once conditions are satisfied on the tested reference.
- If **some other spender** directly reserves backing, this app has no ability to release that outsider's reservation. A guarantee of eventual exit requires each reservation to be entered through a recognized time-bound spender at creation. Legacy stranded locks are not retroactively recoverable.
- ETH amount is held in the `ReservableConditionalETHReference` contract, NOT this application contract. This profile does NOT advertise strict `IERC721Value` while locks block full burn.
- `termsHash` binds a byte string agreed elsewhere. The contract does **not** validate the meaning or fairness of the document; a UI must show the exact amount, token, beneficiary and expiry independently.
- `MAX_DURATION` limits a new proposed expiry relative to proposal creation, but owner and beneficiary should still assess acceptability of the chosen expiry.
- The contract does not upgrade or intervene in active agreements; that reduces administrative discretion but means bugs in either contract can affect the exit path.

## Tests

`test-foundry/BilateralTimeboundReserve.t.sol` covers randomized amounts/durations, owner/beneficiary permissions, transfer before/after acceptance, exact deadline boundaries, expiry by third parties, double release, wrong terms hash, revocation of unused authorizations, multiple independent reservations by the same escrow spender, maximum-duration constraints and exact ETH refunds from the underlying NFT after release.

These tests demonstrate correctness only in the specified EVM/reference setup; passing them is not a third-party audit or proof against every attack.
