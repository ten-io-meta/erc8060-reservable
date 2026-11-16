# Foundry invariant campaign — validated on experimental branch

This branch **does not change runtime contracts**. It adds a Foundry harness and a separate CI job targeting the ETH-backed strict and conditional reference implementations.

Foundry selects handlers' callable functions to generate multi-step sequences; handlers track a separate "ghost ledger" of obligations, owners, locks, approvals, and transfer epochs, without using contract-reported totals to generate expected balances.

### State properties

- `address(strict).balance == strict.totalRedeemableValue() == sum(valueOf(live tokens))` (absent external donations).
- `address(conditional).balance == conditional.totalBacked() == sum(backingOf(live tokens))`.
- `lockedValue(tokenId) == sum(per-spender locked amounts)`, and never exceeds backing.
- `availableValue(tokenId) == backing - locked`.
- `reserveAllowance(tokenId, spender)` matches granted amount minus held allocation **only in the NFT's current transfer epoch**.
- Actual ETH credited to owners on burn/redemption or available-value withdrawal equals the expected amount.
- NFT identifiers monotonically increase and neither reference permits a stale holder's redemption.

### Risk specifically demonstrated

A reservation to a spender who does not release can remain locked indefinitely even after token transfer, revocation of future approvals, and attempts to redeem. **This is a liveness/design limitation, not necessarily a solvency failure**. A policy for cancellation/dispute/expiry belongs to the application layer and should be considered explicitly before funds are exposed.

### Running locally

Install node dependencies and Foundry, and install forge-std:

```sh
npm ci
git clone --depth 1 --recurse-submodules https://github.com/foundry-rs/forge-std.git lib/forge-std
forge test --match-path 'test-foundry/*.t.sol' -vv
```

GitHub Actions runs Foundry in a separate job and does not request network keys. No Ethereum Mainnet deployment or transaction is involved.

**The existence of this document or a passing suite is not proof of production security.** Record the exact CI commit, number of invariant runs, depth, actual non-reverted handler calls, and any minimized counterexamples when reporting.

## Verified CI results (2026-11-16)

Foundry run [#43946663105](https://github.com/ten-io-meta/erc8060-reservable/actions/runs/43946663105) at commit `b9cd7b6` passed using a pinned `forge-std` commit `15b2df92a05d4d2f76a06653872fefb287e0e01c`.

| Verification | Result |
| --- | --- |
| Strict ETH stateful invariants | 96 runs × 64 calls = 6,144 handler calls, 0 reverts |
| Conditional Reservable stateful invariants | 96 runs × 64 calls = 6,144 handler calls, 0 reverts |
| Escrow expiry recovery across NFT ownership change | 256 fuzz inputs passed |
| Unauthorized timed escrow creation | 256 fuzz inputs passed |
| Uncooperative-spender indefinite-lock property | 256 fuzz inputs passed |

The **12,288** handler calls are generated attempts, *not necessarily 12,288 state-changing transactions*: some handlers deliberately return without a state transition once limits are reached or eligibility conditions do not hold. The onchain contract state is compared to independent ghost accounting after every fuzz step. This is meaningful safety evidence but is not exhaustive coverage.

Prior Hardhat run [#43946366401](https://github.com/ten-io-meta/erc8060-reservable/actions/runs/43946366401) also succeeded on the same Solidity contracts, maintaining the previous 174-test baseline.

### What remains unresolved

- A lost or noncooperative spender can indefinitely lock reserved funds in the **core** conditional reference. The timed escrow demo can release on expiry only when **that application** is the spender and its deadline was agreed in advance; it is not a universal escape hatch.
- Timeout release is not trade settlement and grants no entitlement to extract committed ETH. The escrow's `settleTimedEscrow` deliberately reverts.
- Handler fuzz success does not prove every Solidity path, all third-party integrations or future deployments safe.
- Keep `main` and live TEN.IO contracts unchanged; no real ETH wallet was used.
