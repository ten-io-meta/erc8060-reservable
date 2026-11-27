# Disclosure and Indexing Profile

## Status

Informational — experimental reservation-accounting disclosure only, not a strict ERC-8060 redemption profile and not a deployment/security certification.

**For the current ERC-8060 Draft's `valueOf` + `burn` guarantee, ERC-165 identity, and safe wallet detection of reservation-conditioned profiles, read [strict-versus-conditioned discovery](strict-vs-reservation-conditioned-discovery.md).** The accounting mock does not hold actual ETH; its `totalValue` must not be treated as verified backing or immediate redemption.

## Purpose

IERC8060Reservable standardizes reservation accounting.

However, safe use by wallets, marketplaces, agents, and risk engines requires clear disclosure of reservation state and reservation-related events.

This profile describes recommended disclosure and indexing practices for production implementations.

## Core Distinction

Implementations and integrators SHOULD distinguish between:

- actual committed value
- available value
- revocable authorization
- recovery metadata

The core distinction is:

| Concept | Meaning |
|---|---|
| totalValue | Total value recorded by the optional host; not authenticated ETH collateral |
| lockedValue | Value currently committed through active reservations |
| availableValue | Recorded value not currently reserved, possibly usable by the host's accounting functions; not a verified ETH payout or strict burn right |
| reserveAllowance | Revocable authorization to attempt a future reservation |

`reserveAllowance` is not the same as `lockedValue`.

Overlapping reserve allowances may create latent exposure, but only `lockedValue` represents actual committed value.

## Required User-Facing Disclosure

Wallets, marketplaces, and agents SHOULD display:

- totalValue
- lockedValue
- availableValue
- whether active reservations exist
- whether reservations are hard or recoverable when known
- recovery metadata when available

Displaying only `totalValue` is insufficient for reservable ERC-8060 tokens.

## Active Reservation Disclosure

Production implementations SHOULD make active reservation state discoverable either through:

- indexed events
- off-chain indexers
- optional enumeration views
- application-specific metadata

IERC8060Reservable does not require enumeration in the core interface because enumeration introduces storage, gas, and implementation trade-offs.

## Recommended Events

Implementations SHOULD emit events sufficient for external systems to reconstruct reservation state.

Recommended event surface:

```solidity
event ReserveApproval(
    uint256 indexed tokenId,
    address indexed spender,
    address indexed asset,
    uint256 amount
);

event ValueReserved(
    uint256 indexed tokenId,
    address indexed spender,
    address indexed asset,
    uint256 amount
);

event ValueReleased(
    uint256 indexed tokenId,
    address indexed spender,
    address indexed asset,
    uint256 amount
);
```

Indexers can use these events to reconstruct:

reserve approvals
active reservations
released reservations
latent authorization exposure
## Marketplace Guidance

Marketplaces SHOULD NOT display only totalValue.

Listings SHOULD distinguish:

recorded total value (not proof of backing)
recorded locked value (not proof of creditor payment)
recorded unreserved value (not proof of redemption availability)
known reservation applications
recovery status if known

A token with high recorded totalValue but low availableValue may be accounting-encumbered; no conclusion about real collateral or strict ERC-8060 redemption follows without contract-specific verification.

## Risk Engine Guidance

Risk engines SHOULD treat:

lockedValue as actual committed exposure
availableValue as unreserved accounting value (not guaranteed liquidity)
reserveAllowance as latent authorization exposure

Risk engines SHOULD NOT assume that unused reserve allowance is equivalent to active locked value.

Risk engines SHOULD also distinguish between:

hard reservations
recoverable reservations
unknown reservation profiles

Unknown reservation metadata SHOULD be treated as higher risk.

## Transfer Disclosure

Because active reservations travel with tokenId, wallets and marketplaces SHOULD surface reservation state before transfer, listing, purchase, collateralization, or valuation.

A recipient of a reservable token SHOULD be able to see whether value is already locked before accepting or purchasing the token.

## Non-Goals

This profile does not modify the core IERC8060Reservable interface.

It does not require:

universal force release
mandatory enumeration
mandatory marketplace behavior
mandatory recovery semantics
global allowance caps
## Relationship to IERC8060Reservable

IERC8060Reservable remains a minimal accounting primitive.

This profile exists to help external systems correctly interpret and disclose reservation state without adding execution or recovery semantics to the core standard.