# IERC8060Reservable — invariant audit (2026-11-16)

**Scope:** Experimental integration laboratory, branch `audit/reservable-invariant-hardening`. This is a code review with Hardhat regression tests, **not** a formal proof or third-party security audit.

## Accounting invariants examined

| Property | Meaning | Evidence / boundary |
| --- | --- | --- |
| 0 <= locked <= accounted total | No overallocation or negative available value | Reserve/withdraw checks, deterministic state-model test |
| available = accounted total - locked | Every update preserves exact accounting | 64-step, per-state assertions on two NFT IDs and two assets |
| aggregate locks = sum of allocations | Reservation isolation by spender | Model test, released amounts checked against caller's lock; storage aggregation is not publicly enumerable |
| owner-only reserve approval | Unrelated address cannot grant reservation permissions | Existing suite; mock uses owner check |
| reserve capped by approval and available | No overspending or repeated overreservation | Existing tests, combined model and max uint256 coverage |
| release only by reserving spender | Another spender cannot free an allocation | Existing and new regression tests |
| transfer keeps active locks, revokes unused approvals | Buyer inherits commitments, not the old owner's unused spending powers | Epoch tests and model checks |
| burn cannot destroy locked value | Reservation-conditioned burn reverts until unlock | Dedicated ETH-backed burn and conditional profile tests |
| zero-address token protection | Mock must not allow accidental destruction of live ownership with nonzero locks | New zero-address mint and transfer regressions |
| truthful application settlement | Demo must not advertise completion of a nonexistent payout | Hardened original three demos and newly fixed `TimedReservableEscrow` |
| ERC-8060 strict/conditional distinction | A conditional burn profile must not advertise strict redeemability | ERC-165 profile tests |

## Issues corrected in this audit branch

1. `ERC8060ReservableMock` allowed `transferFrom(owner, address(0), id)`, creating a token with no effective owner while associated locks could remain. The mock now rejects zero-address recipients. Lab minting is restricted to the deployer and rejects `address(0)`.
2. `TimedReservableEscrow` allowed arbitrary callers to claim settlement without payout, while leaving a reservation locked and disabling timeout refund. It now restricts creation to the NFT owner/seller, and the unsupported settlement entrypoint always reverts. Deadline refund still releases the original reservation.
3. `docs/commitment-accounting.md` wrongly attributed `totalValue()` to ERC-8060. It now correctly describes this as a laboratory-specific accounting helper.

## Explicit non-guarantees

- **No ETH custody proof in `ERC8060ReservableMock`.** `mintValue` increments book entries without depositing ETH; `withdraw` updates book entries without ETH payout. Hence the mock cannot certify solvency, actual collateral, or ERC-8060 strict redemption.
- A reserved balance may remain locked forever if a spender cannot call `releaseValue`. Recovery, enforceable claims and disputes are application-level design decisions.
- ERC-165 reports interface support, not contract truthfulness or solvency.
- Timeouts, lending and settlement demos must not be used with real funds without their own security assessment, including reentrancy, malicious ERC-721s, value backing and economic fairness.
- The deterministic 64-step model samples operational sequences, not all possible states. Full formal verification and fuzz/property-based testing against live backed implementations remain necessary before production claims.

**Acceptance gate:** Run `npm ci && npm test` in GitHub Actions at the exact latest head SHA and check that the new tests pass before merging. Do not move the experimental branch into `main` on the strength of this review alone.
