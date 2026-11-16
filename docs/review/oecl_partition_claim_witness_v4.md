# OECL v4 — bounded witness for executable ETH collateral portions

**Status: Draft research. No real-funds deployment. Not audited. No changes to strict ERC-8060 or IERC8060Reservable's six-function ABI.**

## Falsifiable objective

Distinguish, without trusting self-declared interfaces or the value quoted by a random NFT, three non-equivalent claims:

1. **ACCOUNTING SURFACE** — an authenticated conditional asset/app supports reservation accounting. This is neither a demonstrated live lock nor an enforceable debt.
2. **PARTITIONED LIQUIDATION NOW** — a recognized, *already-funded* custody loan on a conditional ETH NFT has reached its agreed default+grace deadline; under the fixed reference/app code, a live enforceable **portion** is held with real backing, and the current transaction is eligible to call `liquidate`.
3. **STRICT BURN PROFILE** — a recognized strict ETH-backed ERC-8060 reference exposes whole-NFT redemption. This is not partial collateral extraction and does not itself prove a particular third party is authorized to burn a given token.

Verdicts: `UNKNOWN` for unrecognized provenance; `REJECT` for recognized but incompatible/non-executable state; `ACCEPT` only for the requested, **bounded** capability at observation time.

## Closed-world provenance and trust root

`OECLPartitionedClaimWitness` creates its **own** `OECLPartitionedLoanFactory` through `new` in the witness's real constructor. That factory can deploy **only** `PartitionedReserveLoanPoC` via the real constructor, bound to a conditional reference NFT registered in the existing OECL gate. It cannot admit user-supplied applications or arbitrary NFT implementations.

`OECLPartitionedLoanFactory.boundAsset(app)` is not settable by users and cannot be synthesized by a fake contract. An independently deployed instance of `PartitionedReserveLoanPoC`, even with identical runtime bytecode and valid parameters, is **UNKNOWN**.

**Critical limit:** witnessing the factory's own creation is only meaningful if the witness contract, gate, initial factory contracts and their onchain constructor execution are themselves independently authenticated. This is a **closed-world test harness**, not a universal onchain proof of deployment provenance. Codehash matching alone cannot prove initialized storage.

## Admission checks: partitioned liquidation

The witness requires all of the following:

- asset recognized by the gate as **conditional ETH-backed Reservable**, not strict ERC-8060;
- application deployed through the witness-owned real factory and permanently associated with that NFT;
- trusted app's `nft` and `gate` bindings match that association;
- loan exists, is `Active` (funded with real ETH), has nonzero lender, valid loan terms, and recorded due date;
- ERC-721 `ownerOf(tokenId)` is the custody application; `activeTokenLoan(tokenId)` matches the requested loan;
- NFT contract is globally solvent; per-token backing >= collateral, aggregate locks >= collateral, and `backing = locked + available`;
- app's real ETH balance covers all outstanding pull credits;
- current timestamp is **strictly greater than** `dueAt + grace`.

The strict-ERC8060 whole-NFT burn capability is assessed separately and never implies partial redemption rights.

### Claim-specific evidence limitation

The six-function `IERC8060Reservable` ABI exposes *aggregate* `lockedValue`, not `lockedBy(tokenId, spender)`. Therefore aggregate locks alone do **not** prove which spender controls a specific portion. This witness infers the loan app's control from **the exact trusted, immutable app/reference implementations**, their authenticated factory-created deployment history, and their onchain funded/custody state. It is **not** an independent cryptographic proof of per-spender lock ownership for arbitrary NFTs.

To generalize this pattern to third-party contracts, an **optional read-only per-spender evidence capability or independently verifiable proof of a specific controller's exclusive lock** may be needed. Do not quietly add it to the six-function core without proving necessity and compatibility.

## Example: 2 ETH backed, two independent applications

| State | A reservation | B reservation | Total NFT backing | B claim verdict |
| --- | ---: | ---: | ---: | --- |
| Before loan | 0.6 ETH | 0 | 2 ETH | REJECT unfunded |
| Funded, before due date | 0.6 ETH | 1.2 ETH | 2 ETH | REJECT not executable yet |
| After `dueAt + grace` | 0.6 ETH | 1.2 ETH | 2 ETH | ACCEPT now-executable path |
| After atomic `liquidate()` | 0.6 ETH | 0 | 0.8 ETH | REJECT loan no longer active |
| After borrower repays instead | 0.6 ETH | 0 | 2 ETH | REJECT loan no longer active |

When liquidated, B recovers exactly 1.2 ETH into fully backed pull credits: lender 1.1 ETH, borrower surplus 0.1 ETH. Application A's 0.6 ETH reservation remains intact.

## Reproducible evidence receipts

`assess(...)` returns structured evidence: identity, loan ID, lender, token ID, nominal collateral, payoff, observed backing, aggregate locked/available ETH, maturity threshold, observation block, verdict, reason and a deterministic evidence hash.

`record(...)` emits `EvidenceReceipt` with the current verdict and hash.

**A receipt is a snapshot, not a transferable permission, audit certificate, future promise or execution commitment.** A repayment or liquidation can change the state after receipt issuance; the eventual executor must verify current conditions in its own transaction. The test suite demonstrates such invalidation.

## Must-pass adversarial cases

1. Accounting app A is accepted as accounting-only but not as liquidating creditor.
2. Strict burn is supported only by strict ERC-8060 profile; conditional reservations are rejected as strict.
3. B must be funded and pass the deadline before executable ACCEPT.
4. AFTER B liquidation or full borrower repayment, claim witness changes to REJECT.
5. Real liquidation must preserve unrelated A reservation and pay lender only real ETH.
6. External app with identical bytecode is UNKNOWN; external NFT identical bytecode is UNKNOWN; fraudulently pre-funded fake NFT is UNKNOWN.
7. A factory-known app paired with a different asset is REJECT.
8. Receipt hash and event are bound to state and block; stale result is observably different.
9. 256 fuzz cases with varying non-overlapping reserve amounts, where every accepted live claim must successfully liquidate and preserve the other lock.
10. Witness and its actual factory must fit EIP-170's **24,576 byte** deployed runtime limit.

## What this DOES NOT prove

- real-world enforceability, all possible EVM interleavings, no reentrancy/MEV attacks or production safety;
- that arbitrary applications can liquidate without **custody** of the NFT;
- any native-ETH redemption through strict ERC-8060 burn for a locked portion;
- authenticity of arbitrary factory addresses or initial storage outside the trusted deployment tree;
- that aggregate per-token reserve totals alone authenticate **specific** spender control;
- that an `ACCEPT` at observation block remains valid in future blocks;
- that `ACCEPT` is a global approval of financial protocols.

The research outcome, if tests pass, is **a bounded, falsifiable execution-witness design**. Next phase: minimize the trust root, prove or refute necessity of a per-spender lock witness, and add hostile stateful interleaving/ghost economic ledger verification. Remain DRAFT until independent review.
