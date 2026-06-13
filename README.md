# IERC8060Reservable

Minimal reservation accounting extension for ERC-8060 value-bearing NFTs.

The extension allows authorized spenders to reserve portions of a token's underlying value without taking custody of the NFT itself.

Status: Draft
Reference implementation and test suite included in this repository.

## Design Review Summary

This extension was intentionally designed as a minimal reservation accounting primitive rather than a generalized escrow or obligation framework.

During adversarial review, several potential additions were considered and rejected:

* Aggregated allowance tracking (`allocatedValue`)
* Standardized settlement or consumption functions (`spendReservedValue`)
* Transfer restrictions while value is locked
* Built-in deadlines or expiration semantics
* Reputation, trust, or priority signals
* Dispute resolution or liquidation logic

None of these survived reduction without moving from accounting into application-specific execution or risk judgment.

The resulting design maintains a strict separation of concerns:

| Layer                              | Responsibility                        |
| ---------------------------------- | ------------------------------------- |
| ERC-8060                           | Value custody and `totalValue`        |
| IERC8060Reservable                 | Reservation accounting                |
| Escrows / Applications             | Settlement, execution, and conditions |
| Reputation Systems (e.g. ERC-8004) | Identity, trust, and discoverability  |
| Risk Engines                       | Interpretation and underwriting       |

`IERC8060Reservable` standardizes only the following:

* `reserveAllowance`
* `reserveValue`
* `releaseValue`
* `lockedValue`
* `availableValue`

Reservations and locked value are bound to the `tokenId` and travel with the NFT upon transfer.

`reserveAllowance` represents revocable authorization, not a binding commitment.

The extension deliberately excludes settlement semantics, dispute resolution, liquidation rules, deadlines, reputation systems, and business logic.

Multiple adversarial reviews identified no missing protocol primitive, no internal contradiction among the invariants, and no irreducible failure mode originating from the accounting layer itself.

The design is therefore considered to have reached **protocol closure** for reservation accounting.
