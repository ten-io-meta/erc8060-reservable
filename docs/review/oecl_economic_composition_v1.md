# OECL Economic Composition — Experiment 1 (falsification)

> **Experimental scope only.** Do not deploy with user funds. No ERC-8060 or IERC8060Reservable ABI changes. No claim of an independent audit or formal proof.

## Hypothesis under test

> A small set of economic primitives, with verifiable composition rules, lets independently developed applications cooperate while preserving backing, exclusivity, authorization, and execution guarantees, **when their capabilities and trust assumptions are compatible**.

The phrase *when compatible* must be testable, not assumed. An onchain account balance or interface assertion alone is not proof of an executable creditor right.

## Actual components

- Asset: `ReservableConditionalETHReference`, an experimental ETH-backed **conditional** reservation profile, **NOT strict ERC-8060**.
- Application A: `BilateralTimeboundReserve`, mutually accepted lock with expiry but no creditor payment.
- Application B: `ReservableRepaymentLoanDemo`, ETH-funded loan with debt repayment and reservation release, but **no forced default liquidation**.
- Comparison boundary: `CustodiedCollateralLoanPoC`, the strict-profile custody-and-liquidation alternative. Its constructor rejects the conditional profile rather than silently promising that it can liquidate its NFT.

A and B are separate deployed application contracts calling the same tokenId on one ETH-backed NFT contract.

## Invariants and admission rules (candidate OECL v1)

| ID | Rule | Evidence strategy | Classification |
| --- | --- | --- | --- |
| E-01 | `totalBacked <= actual ETH balance`; per-token backing covers `locked + available` | state reads plus independent ghost ledger in extended campaigns | Accountable local safety |
| E-02 | Sum of independent live reservations never exceeds per-token backing | A+B adversarial sequencing and fuzz tests | Accountable local safety |
| E-03 | Unauthorized actors cannot extract value or release another application's lock | negative authorization tests | Local authority boundary |
| E-04 | A reservation is **not** a payable creditor claim. Reject any asserted `ENFORCEABLE_ON_DEFAULT` capability absent an actual validated claim path | funded debt past due; no lender credits, no collateral transfer or burn, no lender release privilege | **Composition REJECT** for debt enforcement |
| E-05 | NFT transfer preserves established locks, but does not transfer the lock-controller's permission to the purchaser | transfer, owner revoke, release/redeem reverts | Safety with liveness limitations |
| E-06 | `STRICT_BURN` and `CONDITIONAL_RESERVABLE` are distinct capability profiles; do not treat one as the other | strict custody constructor must reject conditional ref | **Incompatible composition** |
| E-07 | A payment counts only if real ETH is credited and withdrawable; lock state alone is never debt settlement | repayment, lender withdraw, and final redemption | Application-level execution (repayment path only) |
| E-08 | Contract bytecode, constructor provenance, initial storage and onchain redemption behavior must be authenticated before using the asset as valuable collateral | future hostile deployment/factory tests | **Unverified**, not satisfied by this experiment |
| E-09 | Expiry of an accounting-only reservation does not prove default recovery or debt settlement | A expires; B stays funded and reserved | **Composition REJECT** for creditor enforceability |

`E-04` and `E-09` are intentionally **negative** results: the test should pass when it reproduces a safely accounted yet *economically unenforceable* loan.

## Smallest counterexample

1. Mint a conditional NFT with **2 real ETH**.
2. A reserves **0.6 ETH** for a beneficiary via bilateral acceptance.
3. B independently reserves **1 ETH**, and its lender transfers **1 real ETH** to the borrower as principal.
4. Total locked is **1.6 ETH**; available is **0.4 ETH**. Backing and authorization remain correct.
5. The debt becomes overdue. `ReservableRepaymentLoanDemo` has no default liquidation or lender extraction path.
6. The lender cannot release its own protocol's lock, burn the NFT, or withdraw the locked collateral. It has **zero** withdrawable repayment credit until an actual payer repays.
7. A can legitimately expire and release 0.6 ETH, but that still does not pay B.
8. The NFT holder may withdraw unreserved ETH; the B reservation continues to block full redemption. A purchased/ transferred NFT inherits the locks without giving the buyer enforcement rights.

**Interpretation:** two individually correct accounting applications compose safely for reservation accounting, but there is no automatic guarantee of economic recovery for a funded loan. This is **not a demonstrated double-spend** and is **not** evidence of a broken six-function reservation ABI.

## Expected evidence matrix

| Scenario | Accounting | Creditor execution | OECL verdict |
| --- | --- | --- | --- |
| A+B locks, full borrower repayment and both releases | Valid | Real lender repayment succeeds | ACCEPT for this limited path |
| A+B attempted over-reservation | Reverts atomically | No new claim | REJECT |
| A+B funded loan, no repayment past due | Valid and solvent | Lender cannot force recovery | REJECT enforceable-collateral claim |
| A+B NFT transfer carrying locks | Preserved | Still no default path | ACCEPT accounting; REJECT enforcement |
| Attempt to pass conditional NFT into strict custody liquidator | N/A | Constructor rejects profile | INCOMPATIBLE |

**Important:** ACCEPT for a tested repayment path is **not** approval for production or evidence that arbitrary applications are safe.

## Reproducible execution

```bash
forge test --match-contract EconomicCompositionV1Test -vv
forge test
npm test
```

GitHub Actions run against exact commit SHA is necessary. Random fuzz inputs are not a proof of complete coverage. Enrich future runs with handler-based stateful scheduling, ghost economic claim ledgers, reentrancy traces, and execution receipts.

## What would falsify the larger thesis?

1. A counterexample violating `E-01` through `E-03` **within the declared trusted reference and authorization model**, regardless of application scheduling.
2. A composition marked ACCEPT under explicit verified permissions/capabilities where an adversarial sequence still violates the promised economic outcome.
3. An irreducible enforcement requirement not expressible through any sufficiently minimal custody/claim-path adapter without changing the underlying accounting ABI.

## Next research milestone

Design a narrow **capability-and-enforcement witness**, verified against a canonical immutable deployment, that distinguishes:
- account-only lock (`RESERVE_ACCOUNTING`),
- owner withdrawable available value (`OWNER_WITHDRAW`),
- executable creditor claim (`CREDITOR_SETTLE`),
- full burn redemption (`STRICT_BURN`).

Treat claims with unknown or unverified witnesses as **UNKNOWN/REJECT**, never default ACCEPT. OECL records declarations, local evidence and counterexample receipts; a registry declaration by itself is not a proof. Do not extend the IERC8060Reservable six-function interface until a concrete impossibility result justifies it.
