# External security audit brief — Reservable research prototypes

**Status: AUDIT REQUEST PREPARATION ONLY. No external auditor has been appointed, no independent audit completed, no production approval.**

Scope repository: https://github.com/ten-io-meta/erc8060-reservable
Code baseline: `main` merge commit `fdbfc409186db45b173aa4f01e8d574d09a3eab3` plus the prospective disclosure/audit-reproduction PR. Independent reviewers MUST pin their own exact commit hash before issuing any conclusion. The publicly merged [ERC-8060 Draft](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-8060.md) is a separate specification with a distinct ETH-backed reference repository.

## 1. What does and does not exist

This repository implements six **experimental reservation accounting** functions:

`approveReserve`, `reserveAllowance`, `reserveValue`, `releaseValue`, `lockedValue`, and `availableValue`.

It contains `ERC8060ReservableMock`, a deliberately **synthetic** accounting host, and four application examples: `MinimalReservableEscrow`, `TimedReservableEscrow`, `MinimalLendingCollateral`, `AgentTaskBond`. The mock does NOT implement ERC-721, native-ETH custody, the strict `IERC721Value.valueOf` and `burn` interface, or an authenticated ERC-165 conditional-redemption profile. `mintValue` records numbers without funding; `withdraw` adjusts a mapping without paying. App functions named `settle` often mark flags or log events without settlement transfers. A passing Hardhat test is not evidence of a funded creditor claim.

The `demo/` website is a local JavaScript calculator using fictitious units and a simulated holder label. It has no blockchain, wallet, RPC, deployed contracts, transfer, payout, ETH, or settlement. Do not treat page values as enforceable collateral.

## 2. Reproducible negative findings — deliberately NOT fixed in these prototypes

The tests at `test/ExternalAuditReproduction.test.js` reproduce the exact behavior below with deterministic local actors. A passing test means the unsafe behavior **is still possible**, not that it has been remediated.

| ID | Code boundary | Observable issue | Impact IF mistakenly reused in a financially active implementation | Proposed auditor concern |
| --- | --- | --- | --- | --- |
| R-01 | `ERC8060ReservableMock.transferFrom` + `_clearUnusedReserveAllowances` | The latter is an empty stub: unused permission from the previous owner remains available for the old spender after ownership transfers | Unexpected new reservations can encumber assets for a new owner | High |
| R-02 | `ERC8060ReservableMock.mintToken` | Any caller can assign an unminted bookkeeping token ID to an address | No authenticated issuance or provenance guarantees | High |
| R-03 | `MinimalReservableEscrow.settleEscrow` | Any caller can mark an escrow settled; no actual payment occurs and recorded lock remains | False positive settlement signals and stranded accounting entries | High |
| R-04 | `MinimalReservableEscrow.releaseEscrow` | Any caller may release an active accounting escrow, independent of role | Intended commitment can be cancelled by third parties | High |
| R-05 | `MinimalLendingCollateral.closeLoan` | Any caller may close a position and release its accounting reservation | Third-party invalidation of purported collateral lock | High |
| R-06 | `demo/index.html`, `demo/app.js`, historical documentation | Formerly rendered simulated counters as "ETH" and suggested ERC-8060 treasury/settlement outcomes | False impression of backing, strict redemptions or audited custody | Public-disclosure hazard — addressed by this PR |

These are preliminary **internal observations** with hypothetical deployment impact; severity is not an independent auditor's rating. The examples are explicitly not deployment-ready. The public-disclosure fix must not be interpreted as repairing R-01 through R-05. No actual user funds are reported affected.

## 3. Independent review work requested

An auditor with no authorship or editorial dependence on the prior project findings should independently:

1. **Establish scope and provenance:** pin the source commit, Solidity compiler, exact dependency-lock digests, build settings, bytecode, deployed addresses (if any), proxies, immutable/constructor args, trusted factory origin, ERC-165 responses, and reproducible contract identity. Runtime codehash alone is not sufficient to authenticate constructor-selected storage.
2. **Verify specification boundary:** contrast native-ETH strict ERC-8060 `valueOf(tokenId)` and owner-only atomic `burn(tokenId)` against this *asset-qualified*, noncustodial-in-the-mock reservation interface. Verify that a reservation-conditioned profile cannot silently claim strict redemption while a lock blocks payout. Do not invent an ERC-165 identifier for a nonexistent standard profile.
3. **Falsify accounting invariants:** model `0 <= locked <= total` per token and asset, no underflow, per-spender tracked commitments, overlapping allowances, partial releases, conservation, multi-owner transitions, approvals before/after transfer, ID reuse, asset units, untrusted token implementations, release timing, reentrancy, and griefing.
4. **Test authority and execution:** reject unauthorized issuance, releases, settlements, loan closure, bond settlement, timed refunds, and permission carryover across owners. Separate events and boolean status changes from paid ETH or enforceable creditor rights.
5. **Verify actual value transfer if a financial host is proposed:** lock a *source-pinned, funded* contract in an isolated EVM with native ETH; compare balances, per-owner rights, failed-recipient rollback, complete atomic settlement, post-transfer permissions, adversarial reentrancy and reversible ablations. No live funds or RPC access should be required for this analysis.
6. **Challenge disclosure and claims:** inspect the actual public Github Pages asset (not just GitHub source); prove the page discloses its simulated nature in default state and after all interactive actions. Validate that `totalValue`, `lockedValue`, `availableValue` and all allowances cannot be confused with *redeemable ETH now*. Test stale listing/settlement snapshots.
7. **Test coverage independently:** produce an adversarial test model not merely calling the repository's helper expectations; include negative examples with actual contract-owner ETH rejection and any separate profile-detection assumptions.

The owner-only ETH-rejecting contract case is covered in the **separate ERC-8060 reference** repository; do not equate that result with any `ReservableMock` payout test.

## 4. Required independent deliverables and acceptance gates

- Written threat model and exact scope/out-of-scope with frozen commit and bytecode hashes.
- Detailed findings with severity and independently reproducible PoC/test commands; distinguish observed source flaws from hypothetical consequences.
- Proposed remediations and retests with before/after evidence, including R-01 through R-05 if these examples will ever become production candidates.
- Independent confirmation of asset funding, payout, permissions, ERC-165/proxy provenance and marketplace atomic settlement if production use is intended.
- Explicit statement of which implementations and networks the conclusion does (and does not) cover.
- An identified third-party reviewer and their publicly verifiable report before describing the code as "independently audited".

**Release status: BLOCKED for entrusted ETH/collateral, lending or escrow funds.** Documentation and mock-only demo publishing may continue as research, provided warnings stay prominent. No audit certificate, production deployment authorization, guarantee of safe redemptions or broadly claimed protocol closure is implied.

## 5. Reproduction

From a fresh clone at the audited commit (Node/Hardhat versions from the lockfile):

```bash
npm ci --ignore-scripts --no-fund
npx hardhat test
npx hardhat test test/ExternalAuditReproduction.test.js
node --test scripts/check-public-disclosure.test.cjs
```

`test/ExternalAuditReproduction.test.js` deliberately asserts **unsafe** outcomes; it is a *regression against hiding the limitations*, not a security-fix suite.

Internal investigation and test coverage are valuable inputs for an external audit, **not independent attestation**.
