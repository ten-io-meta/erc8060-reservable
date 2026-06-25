# IERC8060Reservable
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20850524.svg)](https://doi.org/10.5281/zenodo.20850524)
Minimal reservation accounting extension for ERC-8060 value-bearing NFTs.

The extension allows authorized spenders to reserve portions of a token's underlying value without taking custody of the NFT itself.

**Status:** Draft

## Live Demo

https://ten-io-meta.github.io/erc8060-reservable/demo/

Interactive demonstration of:

- reserveValue()
- releaseValue()
- transfer persistence
- multi-application coexistence
- availableValue vs lockedValue

Current repository status: 61 passing tests.

Reference implementation, test suite, escrow example, lending example, timed escrow example, and agent bond example included in this repository.

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

The included examples demonstrate that reservation accounting is sufficient to support multiple independent application-layer workflows without modifying the standard itself.

Current examples validate:

* Escrow workflows
* Agent task commitments
* Lending collateral commitments
* Timed escrow recovery patterns

while preserving the original architectural separation:

| Layer              | Responsibility                  |
| ------------------ | ------------------------------- |
| ERC-8060           | Value custody                   |
| IERC8060Reservable | Reservation accounting          |
| Applications       | Settlement and execution        |
| Reputation Systems | Identity and trust              |
| Risk Engines       | Interpretation and underwriting |

The repository intentionally demonstrates that increasingly sophisticated workflows can emerge without expanding the reservation accounting surface itself.

---

## Example Applications

### MinimalReservableEscrow

Demonstrates escrow-style workflows without transferring NFT ownership or introducing settlement semantics into the reservation layer.

Properties demonstrated:

* Value reservation
* Value release
* No custody transfer
* No NFT transfer
* Transfer persistence
* Allowance enforcement

### AgentTaskBond

Demonstrates agent coordination workflows using reservation accounting.

Properties demonstrated:

* Task bond creation
* Multiple concurrent bonds
* Reservation accumulation
* Independent bond release
* Independent bond settlement
* Invalid state protection
* Allowance enforcement
* Available value enforcement

### MinimalLendingCollateral

Demonstrates lending-style collateral commitments using reservation accounting.

Properties demonstrated:

* Loan collateral locking
* Independent coexistence with escrows and task bonds
* Transfer persistence
* Independent collateral release
* Shared accounting across applications

### TimedReservableEscrow

Demonstrates application-layer recovery mechanisms without modifying IERC8060Reservable.

Properties demonstrated:

* Deadline-based expiration
* Refund of abandoned reservations
* Recovery from inactive counterparties
* Anti-griefing application pattern

---

## Test Status

Current test suite validates:

### Core Reservation Accounting

* Reservation creation
* Reservation release
* Available value accounting
* Locked value accounting
* Allowance enforcement
* Double-spend prevention

### Adversarial Scenarios

* Exact exhaustion
* Over-allocation prevention
* Release order independence
* Double release protection
* Invalid state transitions
* Concurrent application interactions

### Transfer Persistence

* Active reservations survive NFT transfers
* Active obligations remain attached to the tokenId
* New owners inherit reservation state
* New owners can use remaining available value

### Multi-Application Validation

* Escrow coexistence
* Agent bond coexistence
* Lending coexistence
* Independent release paths
* Independent settlement paths

### Multi-Asset Validation

* Asset-level reservation isolation
* Independent accounting per asset

### Multi-Token Validation

* Token-level reservation isolation
* Independent accounting per tokenId

### Timed Recovery Validation

* Deadline-based refunds
* Expired escrow recovery
* Recovery without modifying IERC8060Reservable

**Current repository status: 61 passing tests.**

---

## Security Considerations

### Dead Reservations

If an authorized application reserves value and later becomes inaccessible, the reserved value may remain locked indefinitely.

Examples include:

* abandoned escrow contracts
* lost administrative keys
* broken upgrades
* permanently paused applications
* governance failures

IERC8060Reservable deliberately does not define a universal force-release mechanism.

A universal force-release would weaken reservation credibility for applications such as:

* lending collateral
* escrows
* agent task bonds
* conditional commitments

Instead, recovery mechanisms are intentionally delegated to application-layer contracts.

Applications SHOULD implement explicit recovery paths where appropriate, including:

* deadline-based refunds
* arbitration-controlled releases
* governance-controlled recovery
* bonded application designs
* upgrade safety constraints

The included `TimedReservableEscrow` example demonstrates one such recovery pattern.

### Secondary Market Disclosure

Applications, wallets, and marketplaces SHOULD display:

* totalValue
* lockedValue
* availableValue

Displaying only `totalValue` may misrepresent the economically usable value of a token with active reservations.

Users and applications SHOULD evaluate both available and locked value when assessing token liquidity, collateralization, or market value.

## Production Considerations

IERC8060Reservable intentionally provides reservation accounting only.

The standard does not define:

* execution semantics,
* liquidation logic,
* escrow settlement,
* recovery mechanisms,
* marketplace behavior,
* disclosure requirements.

These concerns belong to application-layer implementations and optional profiles.

### Recoverability

Applications SHOULD explicitly declare whether reservations are:

* Hard Reservations
* Recoverable Reservations

Hard reservations may result in permanently locked value if the reservation controller becomes unavailable.

Production applications SHOULD carefully evaluate whether recovery mechanisms are appropriate for their use case.

See:

* Recoverable Applications Profile

### Disclosure

Wallets, marketplaces, agents, and indexers SHOULD display:

* totalValue
* lockedValue
* availableValue

Displaying only `totalValue` may misrepresent the economically usable value of a token with active reservations.

Unknown reservation metadata SHOULD be treated as higher risk.

See:

* Disclosure and Indexing Profile

### Protocol Closure

Multiple hostile review rounds, adversarial testing, and independent analysis were unable to identify a transaction sequence capable of violating the documented accounting invariants.

Remaining concerns were consistently classified as:

* Integration Layer
* Application Layer
* Disclosure Layer
* Recoverability Layer

No missing mandatory accounting primitive was identified.

## Protocol Closure

Multiple adversarial reviews, application-layer implementations, and test expansions have failed to identify any missing reservation-accounting primitive.

The current repository demonstrates:

* Reservation accounting without custody transfer
* Reservation accounting without ownership transfer
* Multiple concurrent commitments
* Multi-application coexistence
* Multi-asset isolation
* Multi-token isolation
* Transfer persistence
* Recovery patterns implemented entirely at the application layer

No additional accounting primitive has been required to support these behaviors.

The design is therefore considered to have reached protocol closure for reservation accounting.

---

## Core Principle

IERC8060Reservable remains a reservation accounting primitive.

It does not define:

* Settlement
* Liquidation
* Reputation
* Dispute resolution
* Deadlines
* Slashing
* Governance
* Business logic

These concerns remain intentionally delegated to application-layer contracts.

The purpose of the standard is not to execute commitments.

The purpose of the standard is to account for committed value.
