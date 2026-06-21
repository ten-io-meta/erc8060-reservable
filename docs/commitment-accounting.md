# Commitment Accounting for ERC-8060

## Motivation

ERC-8060 introduces value-bearing NFTs through `totalValue()`.

However, many real-world applications require value to be committed without:

- transferring the NFT
- transferring custody
- withdrawing value
- consuming value

Examples include:

- lending collateral
- escrows
- agent task bonds
- service commitments
- timed guarantees

These applications require accounting for commitments rather than moving assets.

---

## Observation

The missing primitive is not settlement.

The missing primitive is commitment accounting.

Applications need a way to express:

> This portion of value is temporarily unavailable for other commitments.

without requiring:

- custody transfer
- asset transfer
- ownership transfer

---

## IERC8060Reservable

IERC8060Reservable introduces a minimal reservation layer on top of ERC-8060.

Core functions:

```solidity
reserveValue(...)
releaseValue(...)
reserveAllowance(...)
lockedValue(...)
availableValue(...)
```
The extension only tracks commitment accounting.

It does not define:

settlement
liquidation
disputes
deadlines
reputation
business logic
Design Principle

The standard separates:

Layer	Responsibility
ERC-8060	Value custody
IERC8060Reservable	Commitment accounting
Applications	Execution and settlement
Reputation Systems	Trust and discoverability
Risk Engines	Interpretation and underwriting
Properties

The model guarantees:

no over-allocation
no double reservation
no double release
transfer persistence
ownership independence

Reservations are attached to tokenId.

They are not attached to the token owner.

Practical Validation

The repository includes:

Lending collateral example
Escrow example
Agent task bond example
Timed escrow example
Interactive demo
Comprehensive adversarial test suite

Current validation covers:

concurrent commitments
commitment isolation
ownership transfer
release ordering
exhaustion scenarios
allowance edge cases
Conclusion

ERC-8060 provides value-bearing NFTs.

IERC8060Reservable provides commitment accounting for that value.

Together they enable applications to coordinate value without transferring ownership, custody, or execution authority.

The reservation layer remains intentionally minimal and delegates settlement semantics to application-layer protocols.