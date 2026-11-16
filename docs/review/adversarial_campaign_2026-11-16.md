# Adversarial state-machine attack campaign — 2026-11-16

**Target:** merged `tests/reservable-integration` implementation, strict `ERC8060NativeETHReference` plus `ReservableConditionalETHReference`, together with existing Reservable accounting demos.

**Execution:** [GitHub Actions #43943207780](https://github.com/ten-io-meta/erc8060-reservable/actions/runs/43943207780), test branch at `10ec2df`.

**Result at this commit:** 174 passing tests, 0 failures (159 preexisting + 15 new). The model-based campaign executed **1,480 seeded, adversarial EVM state transitions**: eight 140-step conditional traces and four 90-step strict traces. Separate reentrancy, MaxUint256 approval and uncooperative-spender checks also passed.

## What was attacked

| Attack / adversarial property | Test outcome |
| --- | --- |
| Over-reserve ETH despite a maximum 256-bit allowance | Reverts correctly |
| Withdrawal exceeding per-token unreserved ETH | Reverts correctly |
| Spender spending after NFT transfer invalidates the previous approval epoch | Prevented |
| Live reservations after NFT ownership changes | Persist as specified |
| Revocation below an existing lock | Original lock persists; new room zero |
| Third-party approvals, releases and withdrawals | Revert |
| Unauthorized ERC721-operator redemption | Reverts; only actual owner can burn/redeem |
| ERC721 safe mint callback attempts immediate reentrant redemption | Blocked |
| ETH payout callback attempts to redeem a second owned NFT before first redemption completes | Blocked |
| Redeem NFT with active reservations | Reverts |
| 1,480 transitions affecting backing, locked, available, total liabilities and actual EVM ETH | No sampled invariant violation |
| Cooperative settlement after arbitrary sequence | Remaining live claims are returned; contract balance and booked liabilities reach zero |

## Economic invariants sampled

For every successful state transition (full per-token scans periodically):

- `address(contract).balance == totalRedeemableValue` for strict reference, absent donations.
- `address(contract).balance == totalBacked` for conditional reference, absent donations.
- `totalBacked == sum(backingOf(tokenId))` across modeled live tokens.
- `lockedValue(tokenId) == sum(spender.locked for tokenId)`.
- `0 <= lockedValue(tokenId) <= backingOf(tokenId)`.
- `availableValue(tokenId) == backingOf(tokenId) - lockedValue(tokenId)`.
- `reserveAllowance(tokenId, spender) == max(approved - spender.locked, 0)` **only** when the spender approval epoch matches the NFT's current ownership epoch; otherwise zero.
- Transfers preserve active locked allocations and invalidate older unused approvals.

## Important liveness finding: intentionally unrecoverable locks

**Risk category:** design-level liveness / availability, NOT a verified exploit against accounting integrity.

Reproduction: token owner approves a spender for the entire ETH backing; spender reserves it; NFT transfers to a new owner; that owner revokes future permissions. With full value still locked, the new owner **cannot** redeem, withdraw or release that spender's existing allocation. The only release authority is the original spender. A lost key or noncooperating spender can make the reservation persist indefinitely.

This behavior is consistent with the current six-function interface and its transfer-preserved commitment model, but must be explicitly disclosed. Application escrow contracts may implement trusted, precommitted timeouts and refund conditions **without altering the six-function core**; such contracts require their own adversarial tests. Arbitrary owner override would weaken the commitment model.

## Important non-guarantees

- Seeds are predetermined so failures can be replayed. These are **reproducible randomized state-machine tests**, not exhaustive symbolic/formal verification.
- No independent third-party audit; no guarantee of production or economic safety.
- Smart-wallet ETH receive incompatibility and application-level settlement fairness are not solved by the passing accounting tests.
- Forced ETH donation tests exist in `test/eth-balance-invariants.js`, separately from these equality checks: with external ETH donations, the correct rule becomes balance >= liabilities.
- **No Mainnet funds or deployed contract were involved.**

## Next recommended checks

1. Increase coverage using property-based mutation/fuzzing (e.g. Foundry invariant harness with independent ghost ledger and handlers).
2. Test an application-layer timelock escrow end to end, including loss of access to spender, boundary timestamps, cancellation permissions, and malicious ERC721 receivers.
3. Verify full ERC-8060 interoperability and economic redemptions under contract-wallet constraints before asserting that the references are suitable for custody.
