# IERC8060Reservable

Minimal reservation accounting extension for ERC-8060 value-bearing NFTs.

The extension allows authorized spenders to reserve portions of a token's underlying value without taking custody of the NFT itself.

**Status:** Draft

Reference implementation, test suite, escrow example, and agent bond example included in this repository.

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

---

## Example: AgentTaskBond

This repository includes a minimal agent coordination example built on top of `IERC8060Reservable`.

The example demonstrates that task commitments can be implemented using reservation accounting without introducing execution, reputation, or settlement semantics into the standard itself.

### Goal

Demonstrate that value can be committed to an agent task without transferring ownership or custody.

### Properties Demonstrated

* Task bond creation
* Multiple concurrent bonds
* Reservation accumulation
* Independent bond release
* Independent bond settlement
* Invalid state protection
* Allowance enforcement
* Available value enforcement

---

## Design Validation

The included examples demonstrate that reservation accounting is sufficient to support multiple application-layer workflows without modifying the standard itself.

Current examples validate:

* Escrow workflows
* Agent task commitments

while preserving the original architectural separation:

| Layer              | Responsibility                  |
| ------------------ | ------------------------------- |
| ERC-8060           | Value custody                   |
| IERC8060Reservable | Reservation accounting          |
| Applications       | Settlement and execution        |
| Reputation Systems | Identity and trust              |
| Risk Engines       | Interpretation and underwriting |

---

## Test Status

Current test suite validates:

* Reservation invariants
* Double-spend prevention
* Transfer persistence
* Escrow integration
* Agent bond integration
* Adversarial state transitions

**Current repository status: 24 passing tests.**

---

## Core Principle

`IERC8060Reservable` remains a reservation accounting primitive.

It does not define:

* Settlement
* Liquidation
* Reputation
* Dispute resolution
* Deadlines
* Business logic

These concerns remain intentionally delegated to application-layer contracts.

---

## Practical Validation

The included examples demonstrate that reservation accounting is sufficient to support real application-layer workflows without extending the standard itself.

The repository currently shows that:

* Value can be committed without transferring ownership.
* Value can be reserved without transferring custody.
* Multiple independent commitments can coexist on the same token.
* Reservation accounting remains separate from execution and settlement logic.

This supports the design goal that `IERC8060Reservable` should remain a minimal accounting primitive while allowing increasingly sophisticated application-layer systems to emerge on top of it.
