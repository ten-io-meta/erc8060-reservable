# IERC8060Reservable

Minimal reservation accounting extension for ERC-8060 value-bearing NFTs.

The extension allows authorized spenders to reserve portions of a token's underlying value without taking custody of the NFT itself.

**Status:** Draft

Reference implementation, test suite, and escrow example included in this repository.

---

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

`IERC8060Reservable` standardizes only:

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

---

## Example: Minimal Reservable Escrow

This repository includes a minimal escrow example built on top of `IERC8060Reservable`.

The example demonstrates that escrow-style workflows can be implemented without extending the reservation accounting surface or introducing settlement semantics into the standard itself.

### Goal

Demonstrate that value can be committed without transferring ownership or custody.

### Flow

1. NFT owner grants reserve allowance to the escrow contract.
2. Escrow reserves value using `reserveValue()`.
3. NFT ownership remains unchanged.
4. Reserved value cannot be withdrawn.
5. Escrow either:

   * releases the reservation
   * settles according to external application logic

### Properties Demonstrated

* No custody transfer
* No NFT transfer
* No double reservation
* Locked value travels with the token
* Settlement logic remains external
* `IERC8060Reservable` remains purely an accounting primitive

### Test Coverage

The example includes automated tests demonstrating:

* Value reservation
* Reservation release
* Transfer persistence
* Allowance enforcement
* Escrow integration

### Design Principle

`IERC8060Reservable` standardizes reservation accounting only.

Settlement, liquidation, dispute resolution, deadlines, reputation systems, and business logic remain application-layer concerns.

---

## Practical Validation

The included `MinimalReservableEscrow` example demonstrates that reservation accounting is sufficient to support escrow-style workflows without modifying the standard.

This supports the design goal that `IERC8060Reservable` should remain a minimal accounting primitive while allowing execution, settlement, and business logic to emerge at the application layer.

The example validates that value can be committed without transferring ownership, custody, or introducing application-specific semantics into the accounting layer.
