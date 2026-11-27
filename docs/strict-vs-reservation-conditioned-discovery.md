# Strict ERC-8060 versus reservation-conditioned value — wallet and marketplace disclosure

**Status:** Informational research and integration guidance, not an EIP amendment, a new ERC-165 registration or a security certification.
**Related:** The officially merged [ERC-8060 Draft](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-8060.md); `contracts/IERC8060Reservable.sol`; `docs/disclosure-and-indexing.md`; the [strict ERC-8060 reference draft PR #6](https://github.com/ten-io-meta/erc8060-native-eth-value/pull/6).

## 1. Do not collapse three economically different values

| Name | API/source | What it describes | What it does NOT prove |
| --- | --- | --- | --- |
| Strict immediately redeemable native ETH | `IERC721Value.valueOf(tokenId)` with strict `burn(tokenId)` | The amount that the current owner is entitled to receive by performing the ERC-8060 atomic burn under its normative guarantees | That the current owner is a contract capable of receiving ETH, or that an untrusted claimed interface is economically sound |
| Total recorded value | Optional `totalValue(tokenId, asset)` in the Reservable accounting host | The host's total recorded amount for this asset and token | That the amount is actual ETH held in escrow, physically recoverable, or equivalent to the strict `valueOf` ABI |
| Locked/reserved value | `lockedValue(tokenId, asset)` | The portion currently committed under active reservations | Guaranteed creditor settlement or a transferable claim |
| Available/unreserved value | `availableValue(tokenId, asset)` | Accounting difference `totalValue - lockedValue`, as enforced by the Reservable host's permitted withdrawal operations | That the **whole NFT** can be burned immediately, or that an arbitrary contract owner can receive the payout |
| Unused reserve authorization | `reserveAllowance(tokenId, spender, asset)` | Permission to create a later reservation | A current lock, a payment, or a commitment |

Important: `IERC8060Reservable` contains six methods (`approveReserve`, `reserveValue`, `releaseValue`, `reserveAllowance`, `lockedValue`, `availableValue`) and three events. It does **not** define `totalValue` in that interface; the host/accounting layer supplies it. It is an experimental reservation interface for ERC-8060-*style* values, not an integrated implementation of the merged strict ERC-8060 Draft.

**The repository's `ERC8060ReservableMock` is a bookkeeping mock.** Its `mintValue` increments a mapping without depositing actual ETH; `withdraw` decrements a mapping without transferring funds; and it lacks ERC-165 `supportsInterface`, strict `IERC721Value` and full ERC-721 implementations. Never use its accounting to claim on-chain ETH backing, strict compatibility, redeemability or a production-standard profile.

## 2. Concrete counterexample from the Ethereum Magicians discussion

Suppose an NFT's associated recorded ETH backing is 1 ETH, with 0.01 ETH actively reserved and 0.99 ETH recorded as `availableValue`.

- Under a **reservation-conditioned** host whose business rule blocks `burn()` while any reservation is active, the immediately executable *full-token* strict burn redemption may be **unavailable**. Do **not** display 0.99 ETH as an immediately payable ERC-8060 `burn()` redemption.
- Under an implementation that permits a distinct partial withdrawal of the 0.99 ETH, that ability is a **different function and different guarantee**, not the merged ERC-8060 owner-only atomic whole-token burn. Check the implementation and relevant locks.
- Even when a smart-contract owner has an unconditional claim to burn, its ETH receipt may revert. An atomic failure preserves the token and obligation but does not grant the owner a fallback withdrawal or guaranteed transfer to an accepting account.
- Active reservations tied to `tokenId` persist across a token transfer in the experimental Reservable design. Display and check reservation state again at settlement; a stale listing-time `valueOf` cannot certify eligibility after another transaction.

**A token with active reservations that cannot honor the unconditional strict ERC-8060 burn guarantee MUST NOT advertise itself as strictly redeemable merely by reporting a positive `valueOf` or responding `true` to a strict ERC-165 interface ID.** This is a proposed interoperability boundary, not a claim that the current mock implements `burn`.

## 3. What can wallets actually detect today?

### Canonical, merged Draft

`IERC721Value` contains both `valueOf(uint256)` and `burn(uint256)`. The strict ERC-165 interface identifier is the XOR of those selectors, `0x88495fe7`.

A historical `valueOf`-only discovery ID, `0xcadf338f`, has been used in research code but **does not by itself identify a strict ERC-8060 implementation**. The two IDs should not be conflated. ERC-165 support is a *self-declared interface signal*; neither ID attests to funding, owner eligibility, code authenticity, a valid proxy implementation, or actual transaction success.

### Optional Reservable interface

The current `IERC8060Reservable` Solidity interface does **not** inherit ERC-165 and does not require `supportsInterface`. This repository's mock does not implement `supportsInterface` at all. **There is currently no agreed ERC-165 capability/profile claim in this repository that automatically identifies an independently verified "reservation-conditioned ERC-8060" deployment.**

A caller who knows a specific verified implementation ABI can attempt *read-only*, asset-qualified `lockedValue(tokenId, asset)` and `availableValue(tokenId, asset)` queries, and can correlate events. But successful ABI calls, events and metadata are not independent guarantees of correct semantics, collateral, authentic factory/constructor identity, or safe settlement. An arbitrary contract can forge compatible function names and values.

### Conservative decision procedure (informational)

1. Resolve chain, exact NFT address, proxy implementation if applicable, deployed bytecode and trusted implementation/factory provenance. **If not authenticated, return UNKNOWN** rather than invent a profile.
2. Query ERC-165 for ERC-721 and strict `0x88495fe7` where available; classify the reply as *advertised capability*, **not verified behavior**. A value-only ID by itself is INSUFFICIENT.
3. Only if a separately authenticated ABI/provenance supports the experimental Reservable layer, request fresh `totalValue(tokenId, asset)` where implemented, `lockedValue`, `availableValue` and relevant commitment metadata; do not assume all ERC-8060 assets are native ETH simply because the optional interface accepts an `asset` address.
4. Confirm conservation, reservation-controller rights, delivery/payout routes and how the concrete implementation handles *full-token burn while a lock exists*. A strict-advertising token that blocks a promised burn on a reservation is **INCONSISTENT WITH STRICT GUARANTEE**, not a compliant hybrid. Unknown authorization, backing or settlement behavior remains UNKNOWN.
5. Present *recorded backing*, *locked*, *available by accounting*, and *immediately executable owner redemption* **as separate UI fields** with different confidence levels. Do not infer an immediately executable payout from an ERC-165 flag, another contract's ETH balance or `availableValue` alone.
6. At marketplace execution, **re-evaluate on the actual chain state and enforce the relevant preconditions atomically in the settlement contract**, including reservation state, owner/payer authority, minimum acceptable value and applicable burn/redemption conditions. Off-chain listing snapshots can become stale; if atomic settlement checks cannot be enforced, do not promise those guarantees.
7. Preserve UNKNOWN, noncompliance flags, errors and adversarial findings; a failed query or a blank interface response does not prove there are no reservations.

This decision procedure is **not implemented as a universal on-chain detector in this PR**. A standardized separately detectable conditional-redemption profile, with unambiguous semantics, version and independent validation, remains an **open interoperability design question**. Do not assign it an invented ERC-165 ID or silently extend strict `IERC721Value`.

## 4. Profile display matrix

| Advertised signal and independently established behavior | Safe presentation |
| --- | --- |
| Strict interface ID advertised and source/receipt evidence confirms unconditional strict burn in applicable context | "Strict ERC-8060 evidence verified within this implementation and scope", with owner-payout caveats |
| Only value-only legacy ID advertised | "Read-only value indicator, strict redemption unverified" |
| Specific Reservable implementation verified and locks block the full strict burn | "Reservation-conditioned; not strict ERC-8060 redemption while blocked" |
| Strict ID advertised yet a reservation breaks strict payout promise | "Advertised strict interface conflicts with observed redemption conditions; do not claim compliance" |
| ABI functions appear present but bytecode, accounting or reservation policy unknown | "Unknown / not independently verified" |
| Reservable bookkeeping mock | "Synthetic accounting-only fixture; no demonstrated ETH custody or redemption" |

The categories are **recommended integration labels**, not standardized statuses returned by the current contracts.

## 5. Cases that must be tested before claiming interoperable settlement

- One token with total recorded value 1 ETH, 0.01 ETH locked and a full burn blocked; `availableValue` remains 0.99 while immediately executable strict `burn` is unavailable.
- A linked reservation interface that truthfully reports locked value but whose ETH backing or actual creditor settlement is missing.
- Unused `reserveAllowance` without an active lock; do not misclassify it as a commitment.
- Transfers with active locked value, and stale/invalidated authorizations from previous owners.
- Contract NFT owners unable to receive native ETH: payout failure reverts token destruction and liability changes; no general recovery is guaranteed.
- Self-reporting ERC-165 `true` or correct bytecode but forged constructor/factory provenance or wrong underlying asset.
- Indexer delay, mempool changes, proxy upgrades and state changes between listing and executed settlement.

Passing unit tests of a bookkeeping contract proves neither real ETH solvency nor the correctness of arbitrary payment and settlement interactions. The older experimental Reservable demonstrations and subsequent OECL research PRs are distinct from the officially merged Draft.

## 6. Non-goals and follow-up

No change to the six-function Reservable ABI, ERC-8060's normative interface, the legacy standard reference code, any escrow agent semantics, or any production wallet/dApp. No automatic escrow, custody, universal rescue, guaranteed creditor payout, arbitrary RPC execution or proprietary control over upstream standards.

A future optional, independently discoverable reservation-conditioned profile would need an explicit *new proposal and security review*, precise `valueOf`/redemption meaning, ERC-165 behavior, ETH-vs-asset units, contract-owner constraints and independently reproducible atomic settlement controls before a wallet could rely on it.
