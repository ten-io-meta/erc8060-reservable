# Commitment Accounting for ERC-8060

## Motivation

The merged strict ERC-8060 Draft defines `valueOf(uint256)` and owner-only atomic `burn(uint256)` for native ETH. It does not define the optional Reservable host's asset-qualified `totalValue(tokenId, asset)` accounting method.

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

IERC8060Reservable proposes a six-function experimental reservation accounting layer for ERC-8060-style values. The present mock does not combine this layer with strict ERC-8060 ETH custody or redemptions.

Core functions:

```solidity
approveReserve(...)
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

Within the local mock's bounded accounting conditions, tests exercise:

- no recorded over-allocation when the expected allowances and states are used
- rejecting duplicate over-release
- persistence of locked entries across a simulated ownership transfer

**These are not real collateral, ETH delivery or unconditional redemption guarantees.** The mock has an acknowledged residual-authorization defect on transfer; see [external review scope](external-audit-scope-and-findings.md).

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

The current files illustrate how *recorded accounting entries* could coordinate applications. They do not prove that funds were deposited, preserved or delivered, nor authorize a production reservation/settlement system.

The reservation layer remains intentionally minimal and delegates settlement semantics to application-layer protocols.