# IERC8060Reservable
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20850524.svg)](https://doi.org/10.5281/zenodo.20850524)
Minimal reservation accounting extension for ERC-8060-style value-bearing NFTs.
> **SECURITY / SCOPE (2026-11).** This is an experimental six-function reservation ACCOUNTING interface, not a strict ERC-8060 full-burn implementation and not an automatic creditor payment right. Historical PR #19 tests deliberately reproduced unsafe baseline outcomes; the hardening branch reverses those tests. This is not a third-party audit. The research PRs #10–16 are stacked, open and NOT present on main as a consolidated audited release; notably [PR #16](https://github.com/ten-io-meta/erc8060-reservable/pull/16) demonstrates forged NFT/factory constructor storage with identical runtime codehash. Never use these demo contracts as real ETH collateral without independently authenticated provenance, economic settlement tests and external audit.


The extension allows authorized spenders to reserve portions of a token's underlying value without taking custody of the NFT itself.

**Status:** Draft

## Strict ERC-8060 versus reservation-conditioned wallet disclosure

The official ERC-8060 Draft defines `IERC721Value` with **both**
`valueOf(uint256)` and `burn(uint256)` (strict ERC-165 interface ID
`0x88495fe7`). This repository's six-function `IERC8060Reservable`
is **optional reservation accounting**, not a strict native-ETH redemption
implementation or a separately standardized ERC-165 profile.

**Read [the profile detection and marketplace disclosure guide](docs/strict-vs-reservation-conditioned-discovery.md)** before displaying a recorded balance as redeemable native ETH. The guide distinguishes total, locked, available and currently executable value, documents the limits of ERC-165 and warns that an actual contract-owner ETH payout may fail atomically.

The bundled `ERC8060ReservableMock` uses synthetic accounting:
`mintValue` does not receive actual ETH, `withdraw` does not pay ETH,
and the mock does **not** implement ERC-165 or strict `burn`. Its
`totalValue` must never be shown as authenticated backing.

## Live Demo — synthetic browser-only accounting

https://ten-io-meta.github.io/erc8060-reservable/demo/

**No wallet, no Ethereum RPC, no on-chain transactions, no actual ETH and no live NFT.**
The JavaScript demo displays invented **demo units** and simulates a holder change
in browser memory. It cannot demonstrate backing, custody, ERC-165 detection,
strict ERC-8060 `burn()` redemption, creditor settlement, or deployment safety.
See [external audit scope and currently reproduced negative findings](docs/external-audit-scope-and-findings.md).

Interactive demonstration of:

- reserveValue()
- releaseValue()
- transfer persistence
- multi-application coexistence
- availableValue vs lockedValue

Earlier published repository baseline: 61 passing tests. This is NOT the latest stacked research branch or an audit certificate; verify exact-head CI for the version under consideration.

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
| ERC-8060                           | `valueOf` and atomic owner-only `burn` (strict profile) |
| IERC8060Reservable                 | Reservation accounting                |
| Escrows / Applications             | Settlement, execution, and conditions |
| Reputation Systems (e.g. ERC-8004) | Identity, trust, and discoverability  |
| Risk Engines                       | Interpretation and underwriting       |

`IERC8060Reservable` standardizes only:

* `approveReserve`
* `reserveAllowance`
* `reserveValue`
* `releaseValue`
* `lockedValue`
* `availableValue`

Reservations and locked value are bound to the `tokenId` and travel with the NFT upon transfer.

`reserveAllowance` represents revocable authorization, not a binding commitment.

The extension deliberately excludes settlement semantics, dispute resolution, liquidation rules, deadlines, reputation systems, and business logic.

Earlier reductions converged on a minimal accounting interface; they did **not** establish a complete proof of financial safety, settlement enforceability, or deployment provenance. The later OECL forged-provenance counterexamples show why authenticated factories, constructor inputs and actual ETH execution must be checked independently.

Accordingly, the six-function ABI is kept stable for research, but **protocol closure is not a security certification or a declaration that all financial use cases are solved**.

---

## Example: Minimal Reservable Escrow

This repository includes a minimal escrow example built on top of `IERC8060Reservable`.

The example demonstrates that escrow-style workflows can be implemented without extending the reservation accounting surface or introducing settlement semantics into the standard itself.

### Goal

Illustrate how accounting commitments can be recorded without moving the *mock's* owner reference or receiving real ETH. This does not demonstrate real asset custody or an enforceable commitment.

### Flow

1. NFT owner grants reserve allowance to the escrow contract.
2. Escrow reserves value using `reserveValue()`.
3. NFT ownership remains unchanged.
4. Reserved value cannot be withdrawn.
5. Escrow either:

   * releases the reservation
   * rejects fake settlement calls because the example has no ETH payout route

### Properties Demonstrated

* No on-chain ETH or NFT custody in this accounting mock
* No change to the mock owner when a reservation is recorded
* No double allocation within the mock's accounting conditions
* Locked accounting entries persist under the mock's holder change
* Application settlement and payout are NOT implemented by the mock
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
* Independent bond state marking (no ETH payment)
* Invalid state protection
* Allowance enforcement
* Available value enforcement

---

## Design Validation

The included examples demonstrate that reservation accounting is sufficient to support multiple independent application-layer workflows without modifying the standard itself.

Current examples validate:

* Synthetic escrow state transitions (not creditor payouts)
* Synthetic agent task commitments (not real bonds)
* Lending-style accounting locks (not loan collateral custody)
* Timed releases of recorded locks (not real ETH refunds)

while preserving the original architectural separation:

| Layer              | Responsibility                  |
| ------------------ | ------------------------------- |
| Strict ERC-8060 implementation (separate) | Actual native ETH backing and owner-only atomic burn, NOT provided by this mock |
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
* Bond settlement disabled: the mock reverts rather than claim payment
* Invalid state protection
* Allowance enforcement
* Available value enforcement

### MinimalLendingCollateral

Demonstrates lending-style collateral commitments using reservation accounting.

Properties demonstrated:

* Loan-style accounting locks only, not authenticated or funded collateral
* Independent coexistence with escrows and task bonds
* Transfer persistence
* Release of recorded accounting locks only
* Shared accounting across applications

### TimedReservableEscrow

Demonstrates application-layer recovery mechanisms without modifying IERC8060Reservable.

Properties demonstrated:

* Deadline-based expiration
* Cancellation of abandoned accounting locks (no ETH refund)
* Timer-based accounting unlock, not funds recovery
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
* Independent application-state transitions; no executable payout or economic settlement

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

**Historical baseline:** earlier published evidence reported 61 passing tests. This is not an exact-head claim for the newer stacked research PRs; consult each branch's CI logs before asserting its current test count.

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

### Limits of historical design reviews

Earlier analyses considered a small, fixed accounting interface convenient for several
synthetic application examples. They did **not** independently certify security,
settlement, deployed source provenance, owner authorization, unconditional redemption,
or prove the absence of other attack sequences.

This repository is **not protocol-closed in a financial-security sense**. Historical PR #19 reproduced prior-owner allowance carryover, unauthorized synthetic issuance, unguarded releases and false settlement flags. A separate hardening branch now invalidates unused old-owner approvals, gates mock issuance and restricts example releases, while disabling fake settlement. However, the host still holds no ETH, borrower-only closing is not creditor approval, and real escrow/loan payment is not modeled. These examples are not production-ready and the six-function interface is not security-certified.

An external auditor has not certified these contracts. The
[external audit scope and findings](docs/external-audit-scope-and-findings.md)
set out the reproduction cases and release prerequisites.

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
