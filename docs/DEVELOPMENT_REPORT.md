# IERC8060Reservable – Development Report

## Status

Draft (Protocol-Closed Accounting Layer)

Repository:
https://github.com/ten-io-meta/erc8060-reservable

Demo:
https://ten-io-meta.github.io/erc8060-reservable/demo/

## Objective

IERC8060Reservable extends ERC-8060 with a minimal reservation accounting primitive.

The goal is to allow applications to reserve portions of embedded token value without transferring NFT ownership or moving value out of the token itself.

The extension intentionally separates:

* value custody
* reservation accounting
* execution
* settlement
* reputation
* risk evaluation

## Standardized Surface

The extension standardizes:

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

Current status:

* 61 passing tests

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

No protocol-layer accounting defect was identified.

No missing mandatory accounting primitive was identified.

## Current Conclusion

IERC8060Reservable appears protocol-closed for reservation accounting.

The remaining concerns identified during review were classified as:

* application-layer concerns
* disclosure concerns
* recoverability concerns
* integration requirements for ERC-8060 implementations

No additional accounting primitive has been demonstrated as necessary.
