# ETH-backed reference candidates (experimental)

These contracts receive native ETH into their own balance and track the exact liabilities associated with each NFT. They are **not** an audit, formal proof, deployed service, accepted ERC or safe-to-use mainnet release.

## Strict ERC-8060 — `ERC8060NativeETHReference`

- `mint{value: x}()` requires `x > 0` and creates an ERC-721 backed by precisely `x` wei.
- `valueOf(tokenId)` reports the current token's genuinely payable ETH.
- `burn(tokenId)` requires the **current owner** and atomically destroys the token, decreases liabilities, and sends the exact value to the owner.
- `totalRedeemableValue` is the sum of unredeemed ETH claims.
- `address(this).balance >= totalRedeemableValue` is the ETH coverage invariant; direct, unassigned surplus is never counted as redeemable backing.
- Only this contract advertises the current `IERC721Value` interface ID in ERC-165.

## Reservation-conditioned — `ReservableConditionalETHReference`

This is **not** strict ERC-8060: a reservation can block terminal redemption.

- Native ETH is actually transferred to the contract on `mint` and `deposit(tokenId)`.
- `backingOf(tokenId)` reports ETH allocated to that live NFT (not necessarily immediately redeemable).
- `totalBacked` tracks all live-token backing; contract balance must cover it.
- All six functions and events of `IERC8060Reservable` are implemented **without changing the ABI**.
- Active locks persist through ERC-721 transfers. Older owners' unused reserve approvals are invalidated on transfer.
- `withdrawAvailable(tokenId, amount)` sends only ETH not committed to outstanding locks; accounting decreases before the external transfer.
- `redeemWhenUnlocked(tokenId)` requires **zero active locks** and the current owner, then burns the NFT and sends its remaining ETH.
- This contract advertises `IERC8060Reservable` in ERC-165 but explicitly denies `IERC721Value`. It intentionally does not expose the strict-standard `burn` or `valueOf` method names.
- ETH surplus/donations are not withdrawable. Recoverability of orphaned locks requires application-layer policies.

## Safety boundaries

- Both contracts use OpenZeppelin ERC-721, `nonReentrant` on payable/external-ETH operations and checks/effects/interactions.
- Neither contract contains privileged backing withdrawal, discretionary confiscation or forced release.
- The strict implementation does not implement Reservable at all.
- The conditional implementation does not claim strict ERC-8060 compliance.
- A blocked or rejecting ETH receiver causes withdrawal/redemption to revert **atomically**, preserving NFT ownership and backing.
- No external marketplace, escrow, interest, credit, slashing or lender-claim semantics are part of these references.
- Solidity is compiled and tested locally in Hardhat: the ETH is **simulated**, not real network funds.
- Before any deployment using valuable ETH, use systematic fuzzing, formal invariant/property checks, adversarial external-contract tests, and independent code review. This work has not met those gates.

## Run

```bash
npm ci
npx hardhat test test/eth-backed-reference.js
npm test
```

The reference uses ERC-8060's current draft from upstream PR #1315; the draft may still change. No modification to that PR is implied by this work.

## Native ETH balance invariant tests

Run `npx hardhat test test/eth-balance-invariants.js` to execute the additional, deterministic **state-model tests**. This suite is separate from the legacy accounting-only mock tests.

- **Strict profile:** 48 sequenced mint / transfer / owner-only burn / rejected unauthorized-burn steps; checks `balance == SUM(valueOf(live tokens)) == totalRedeemableValue` after every transition. Burn tests independently verify the receiver's exact ETH increase net of transaction gas.
- **Conditional profile:** two deterministic seeds, each performing 81 modeled steps over multiple ERC-721 tokens, owners and reservation spenders. Tests compare the model's per-token backing, per-spender locked allocations and remaining allowances against `backingOf`, `lockedValue`, `availableValue`, `reserveAllowance`, `totalBacked` and the EVM contract balance after every transition. Both sequences release all remaining locks and redeem all remaining claims.
- **Rejected payouts:** a contract that refuses ETH is unable to withdraw or redeem. State, NFT ownership, outstanding liability and actual contract balance must all remain unchanged after revert.
- **Unexpected surplus:** a laboratory `SELFDESTRUCT` transfer injects ETH without assigning it to any NFT. Contract assets may exceed total obligations; `isSolvent` must remain true, but reported NFT backing and actual redemption must exclude the surplus.

With no forced surplus, the strict equality is `address(this).balance == totalRedeemableValue` (strict) or `address(this).balance == totalBacked` (conditional). With forced transfers, the solvency invariant is `balance >= liabilities`, and the surplus MUST NOT be counted as a claim.

**Scope:** these are repeatable state-machine traces, **not exhaustive fuzzing or a formal proof**. The tests cover only simulated Hardhat ETH and a limited set of adversarial callbacks. They do not authorize a production deployment or provide guarantees about the broader application layer.

**Validated run:** [GitHub Actions #43915508978](https://github.com/ten-io-meta/erc8060-reservable/actions/runs/43915508978) — 154 passing tests at commit `d33f37a`. Subsequent changes require fresh CI verification.
