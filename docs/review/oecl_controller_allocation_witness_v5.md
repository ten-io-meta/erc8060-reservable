# OECL v5 — independent controller-allocation evidence

> Draft, research-only. No independent security audit, no real funds, no mainnet deployments. **The six-function `IERC8060Reservable` ABI is unchanged.** This reference is still *conditional* and is NOT a strict ERC-8060 burn implementation.

## Why an aggregate counter is insufficient

The six-function `IERC8060Reservable` exposes:
- `lockedValue(tokenId, asset)`: aggregate across every reserving spender,
- `availableValue(tokenId, asset)`: the remainder,
- `reserveAllowance(tokenId, spender, asset)`: **unused authority to create additional locks**, *not* a readout of already locked ETH.

Two states can therefore look identical to a witness which reads only `lockedValue`, `availableValue` and `reserveAllowance` (plus backing, custody and loan ledgers), yet have completely different enforced rights. Specifically:

| Observation | Valid A+B state | Tampered controller-allocation state |
| --- | ---: | ---: |
| Total backing | 2 ETH | 2 ETH |
| Total locked | 1.8 ETH | 1.8 ETH |
| Available | 0.2 ETH | 0.2 ETH |
| Remaining allowance A / B | 0 / 0 | 0 / 0 |
| NFT custody | B | B |
| B funded loan / terms | 1.2 ETH collateral | **Unchanged** |
| **Actual A lock** | 0.6 ETH | **1.8 ETH** |
| **Actual B lock** | 1.2 ETH | **0 ETH** |
| Correct verdict for B's claim | ACCEPT after maturity | **REJECT** |

The tampered state is constructed through **Foundry-only simulated impersonation (`vm.prank`)** of trusted application addresses to show the information-theoretic gap: the same *aggregate* can hide changed controller ownership. This does NOT demonstrate a way to impersonate immutable contracts on mainnet, nor a live exploit of the honest apps.

## Minimal optional evidence interface

The implementation introduces **one view-only** experimental capability in `contracts/IReserveControllerView.sol`:

```solidity
function lockedBy(uint256 tokenId, address controller, address asset)
    external view returns (uint256);
```

Its reference implementation, `ReservableConditionalETHReference`, reads `_reservations[tokenId][controller].locked` **directly from its own storage**. It adds **no new state**, permits **no new authority or movement of funds**, and keeps reservations alive across ownership/approval-epoch changes. Crucially, **it is not added to `IERC8060Reservable`**, is not advertised as the strict ERC-8060 profile, and is not mandatory for existing implementations.

This proves *controller allocation according to the authenticated NFT's authoritative reservation ledger*. It is independent of the application's own `loanInfo` assertion; it is **NOT independent of the NFT implementation's correctness, deployment provenance or custody authority**. ERC165 announcements or an arbitrary NFT's self-reported `lockedBy` cannot substitute for a genuine authenticated storage source.

## Strengthened execution witness and borrower-lender protection

OECL v4's `PartitionedLiquidationNow` witness now reads:
- `controllerLocked` = NFT storage for exactly the loan app's address;
- `otherLocked` = aggregate locked less that exact controller portion, when internally consistent.

It requires **`controllerLocked == loan.collateral`**, in addition to known deployment provenance, actual NFT custody, funded live loan, maturity, backing, aggregate conservation and credit solvency. A mismatched controller balance yields **`REJECT / ControllerAllocationMismatch`**, even if `lockedValue` and `availableValue` are unchanged.

Defense-in-depth: `PartitionedReserveLoanPoC` also verifies its own authoritative `lockedBy` at proposal, funding and liquidation. A mismatch reverts atomically before any collateral withdrawal or ETH credit, preserving unrelated locks. Ordinary `approveReserve` and expired approvals are not mistaken for existing locks.

## Reproducibility / falsification

```bash
forge test --match-contract OECLControllerAllocationV5Test -vv
forge test
npm test
```

Required checks:
1. A=0.6 ETH, B=1.2 ETH, total=1.8 ETH: witness attributes exact amounts to each controller.
2. Simulated mismatched allocation A=1.8 ETH / B=0 ETH, while aggregate backing, allowances and B loan record remain unchanged: witness rejects; real liquidation fails closed.
3. NFT transfer invalidates *approval* but preserves historical controller lock.
4. Parameterized fuzz amounts for A and B, real B liquidation, original A lock intact.
5. All preceding v1-v4 Foundry and Hardhat tests still pass on the exact commit, as do deployment-size assertions.

## What this does NOT solve

- Does not make arbitrary third-party NFTs honest: provenance and real redeemable reserves remain mandatory.
- Does not authenticate the gate's own origin or its factories.
- Does not turn accounting locks into executable debt claims automatically: custody and the application-level partial ETH withdrawal path are still necessary.
- Does not prove permissionless settlement for any app, nor uniqueness of all economic claims outside this NFT ledger.
- Does not prove global temporal liveness, audit correctness, or future repayment.
- Does not establish that every NFT should expose a per-controller getter: this is an **optional evidence surface** whose value is now demonstrated by a concrete falsification experiment. Further formal/standards review must decide whether it should ever become a general interoperability convention.

**Conclusion:** a single optional authoritative read-only getter lets OECL distinguish two states previously observationally equivalent to the six-function accounting interface, without expanding the core standard. This is a bounded proof obligation under authenticated code/deployments, not a universal economic security proof.
