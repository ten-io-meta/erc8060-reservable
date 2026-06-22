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

Funds become releasable after a predefined deadline.

### Arbitration Recovery

An arbitrator can release reserved value after dispute resolution.

### Governance Recovery

A governance process can authorize release after inactivity.

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