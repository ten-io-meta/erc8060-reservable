# Foundry invariant campaign — work in progress

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
