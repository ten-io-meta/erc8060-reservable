# IERC8060Reservable – Development Report

## Status

Draft — experimental accounting model; no independent security audit or production certification

Repository:
https://github.com/ten-io-meta/erc8060-reservable

Demo:
https://ten-io-meta.github.io/erc8060-reservable/demo/

## Objective

IERC8060Reservable is an experimental, optional reservation-accounting interface for ERC-8060-style tokens. It is not an implemented extension of the merged strict native-ETH ERC-8060 burn guarantee.

The goal is to allow applications to reserve portions of embedded token value without transferring NFT ownership or moving value out of the token itself.

The extension intentionally separates:

* value custody
* reservation accounting
* execution
* settlement
* reputation
* risk evaluation

## Standardized Surface

The current research interface declares six methods, not a formally ratified extension:

* approveReserve()
* reserveAllowance()
* reserveValue()
* releaseValue()
* lockedValue()
* availableValue()

Reservations remain bound to tokenId and persist across transfers.

## Design Decisions Evaluated And Rejected

The following proposals were evaluated and intentionally excluded:

* allocatedValue()
* spendReservedValue()
* mandatory settlement primitives
* liquidation primitives
* dispute resolution
* deadlines and expiration semantics
* transfer restrictions
* reputation systems
* governance hooks
* global allowance caps

These concerns were classified as application-layer concerns rather than accounting-layer concerns.

## Optional Profiles

### Recoverable Applications Profile

Documents recovery patterns for applications that wish to support emergency recovery of abandoned reservations.

Examples:

* Timelock recovery
* Governance recovery
* Arbitration recovery

### Disclosure and Indexing Profile

Documents recommended disclosure behavior for:

* wallets
* marketplaces
* risk engines
* agents
* indexers

Including:

* totalValue
* lockedValue
* availableValue
* reservation state visibility

## Reference Implementations

Included:

* MinimalReservableEscrow
* MinimalLendingCollateral
* AgentTaskBond
* TimedReservableEscrow

## Test Coverage

Historical baseline: 61 passing tests; a later exact-head local CI run passed 65 general tests, plus 4 separate disclosure-boundary tests. These are mock accounting and scenario tests, not native-ETH settlement proofs or an external audit.

Coverage includes:

* reservation creation
* reservation release
* allowance enforcement
* transfer persistence
* multi-application coexistence
* multi-asset isolation
* multi-token isolation
* exact exhaustion
* inflation handling
* zero-value protection
* per-spender isolation
* cross-token isolation
* dust accumulation protection

## Adversarial Review

The design was subjected to multiple hostile review rounds.

Review themes included:

* dead reservations
* transfer semantics
* allowance abuse
* overlapping authorizations
* marketplace disclosure
* recoverability
* race conditions
* accounting conservation

That historical review was not an exhaustive search or independent audit. The current mock leaves prior-owner reserve permissions active after a transfer, permits public bookkeeping token creation, and cannot enforce a live ETH payout. See [external audit scope](external-audit-scope-and-findings.md).

## Current Conclusion

The six-function reservation-accounting interface remains an experimental research baseline, with implementation authorization, economic settlement and live ERC-8060 compatibility unverified.

The remaining concerns identified during review were classified as:

* application-layer concerns
* disclosure concerns
* recoverability concerns
* integration requirements for ERC-8060 implementations

No independent reviewer has certified the interface or its applications. The known mock and example limitations must be resolved or excluded before deploying real funds; no lack-of-vulnerabilities claim is made.