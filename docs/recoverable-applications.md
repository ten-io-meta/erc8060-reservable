# Recoverable Applications Profile

## Status

Informational

## Purpose

IERC8060Reservable intentionally standardizes only reservation accounting.

Some applications may require recovery paths to mitigate dead reservation risk resulting from:

- abandoned contracts
- lost administrative keys
- governance failures
- broken upgrades
- permanently paused systems

This document describes a recommended profile for applications that choose to support recovery mechanisms.

## Design Principle

Recovery mechanisms belong to the application layer.

IERC8060Reservable itself remains unchanged.

Applications may voluntarily expose recovery functionality while preserving reservation accounting compatibility.

## Recommended Properties

A recoverable application SHOULD define:

### Recovery Trigger

A clearly specified condition that enables recovery.

Examples:

- deadline expiration
- inactivity period
- arbitration outcome
- governance decision

### Recovery Authority

The entity authorized to execute recovery.

Examples:

- original depositor
- designated arbitrator
- governance contract
- multisig

### Recovery Event

Applications SHOULD emit explicit events when recovery occurs.

Example:

RecoveryExecuted(
    uint256 tokenId,
    address asset,
    uint256 amount
)

### User Disclosure

Applications SHOULD clearly disclose:

- whether recovery exists
- recovery conditions
- recovery authority
- expected recovery delay

## Example Recovery Patterns

### Timed Escrow

A recorded reservation may become releasable after a predefined deadline; this does not refund ETH.

### Arbitration Recovery

An arbitrator may be permitted by a separately reviewed implementation to release the accounting lock after a dispute; no payment is implied.

### Governance Recovery

A governance process might authorize an accounting release, subject to separately verified permissions; this does not execute a payout.

## Non-Goals

This profile does not modify:

- reserveAllowance
- reserveValue
- releaseValue
- lockedValue
- availableValue

It does not introduce:

- universal force release
- mandatory deadlines
- mandatory governance
- mandatory arbitration

## Relationship to IERC8060Reservable

IERC8060Reservable supports both:

- hard reservations
- recoverable reservations

The choice belongs to the application layer.