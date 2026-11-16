# OECL Experiment 3 — Partitioned, executable ETH collateral under concurrent reservations

> **RESEARCH ONLY.** The prototype uses `ReservableConditionalETHReference`, which intentionally does **not** claim the strict ERC-8060 `IERC721Value` interface. It is not audited; do not deposit real user assets.

## Question

Can two independently developed applications utilize distinct ETH-backed portions of the *same NFT*, without releasing each other's active locks, while a creditor's collateral promise is economically executable after default?

## Construction — no change to the six-function Reservable extension

- The NFT owner mints a **2 ETH** conditional reference NFT (via the previously constructed OECL canonical-asset factory).
- Application A (`BilateralTimeboundReserve`) receives an accepted **0.6 ETH** accounting lock, with its own beneficiary and expiry. It NEVER receives creditor settlement rights.
- Application B (`PartitionedReserveLoanPoC`) receives the **same NFT into actual ERC-721 custody** and, as the new owner, approves/reserves only its **1.2 ETH** collateral slice. The previous A lock persists across transfer; prior unsigned reserve approvals are invalidated.
- Lender transfers **1 ETH** into B, atomically forwarded to borrower. The contractual payoff is **1.1 ETH**.
- During a valid full ETH repayment, B credits lender and releases only its lock; borrower can separately recover the NFT, still subject to A's reservation.
- After due date + grace, B can `liquidate()`: in **one indivisible transaction** it calls `releaseValue` for its own **1.2 ETH**, then `withdrawAvailable` as actual token owner, checks exactly **1.2 ETH** received, checks collateral backing decreased by exactly **1.2 ETH**, checks the other **0.6 ETH** remains locked, and credits the lender **1.1 ETH** and the borrower **0.1 ETH**. The NFT then retains **0.8 ETH** of backing (0.6 ETH reserved by A, 0.2 ETH available). The borrower can claim the residual NFT without disrupting A.
- A can later expire or release its lock under its *own* accepted rules. The owner can then redeem the residual conditional NFT.

### Conservation example

| Stage | NFT backing | A locked | B locked | NFT available | B ETH-backed credits |
| --- | ---: | ---: | ---: | ---: | ---: |
| Initial mint | 2 ETH | 0 | 0 | 2 ETH | 0 |
| A + B funded | 2 ETH | 0.6 | 1.2 | 0.2 | 0 |
| B default + atomic liquidation | 0.8 ETH | 0.6 | 0 | 0.2 | 1.2 ETH |
| A later releases | 0.8 ETH | 0 | 0 | 0.8 ETH | 1.2 ETH (less any withdrawn) |

**No double counting:** NFT backing plus credited-ETH balances is conserved across the liquidation, and unrelated A lock is unaffected. The lender's earlier 1 ETH principal was paid to the borrower at funding; it is not held in the collateral account.

## Verified scope of implementation

The partitioned lender protection requires BOTH:
1. genuine NFT **custody** (not just a reservation), AND
2. the exact, permissioned **claim path** `releaseValue(self)` followed atomically by the native ETH `withdrawAvailable` owner function.

The application cannot release A's allocation, and the borrower cannot withdraw against the NFT while B holds custody. A malicious third party cannot call the reserve release as B or cancel a funded loan. Transaction-order races between full payment and liquidation are mutually exclusive onchain.

## EIP-170 and test gates

Foundry contract-size assertion requires the new loan runtime <= 24,576 bytes. Test scenarios: funded loan / A+B preservation, full repayment, over-reservation, unauthorized third-party/borrower actions, A expiring independently before liquidation, both transaction orderings, unfunded cancellation, unrecognized identical-code reference and fake-value collection, and 256 fuzz cases of variable disjoint lock slices.

### Important limitations / possible counterexamples

- **No strict-ERC8060 + Reservable combined NFT was deployed.** This proves conditional native-ETH reservation *composition*, not that the strict `burn(tokenId)` profile can redeem locked subclaims.
- **No atomic Dutch auction for fractional claims.** B withdraws the pre-agreed backing slice; market premiums, pricing, partial payments, liquidation penalties and sales of an encumbered NFT need separate modeling.
- **No automatic liveness proof.** Someone must submit `liquidate`. A borrower may repay right up to liquidation, and ordering changes which valid outcome occurs. There is no universal forced resolution for abandoned A: A's agreed expiry/beneficiary remains authoritative.
- **No arbitrary-factory trustlessness.** The adapter checks both the conditional reference's exact runtime bytecode and the OECL gate's positive asset registration. The *gate itself*, its three factories and their deployment provenance remain explicit trust roots. No bytecode check by itself proves constructor storage provenance.
- **No per-portion security against malicious NFT source code.** The reference is fixed and requires independent audit, complete stateful cross-contract verification, and economic review. If a different NFT allows a malicious caller to withdraw against committed funds, it is incompatible.
- **No generalized cross-contract settlement.** The experiment proves one sufficient enforcement pattern for a specific fixed-profile native ETH NFT: custody + controlled reserve release + partial withdrawal.
- **No production evidence:** all Ether is local EVM simulation; passing a finite number of tests is not proof of safety.

## Falsifiability criteria

FAIL this experiment if **any** adversarial sequence can:
- extract A's 0.6 ETH backing during B liquidation;
- release A's lock from the loan B / borrower / unrelated address;
- credit lender without receiving actual ETH in the adapter;
- make liquidation transfer more than B's collateral slice;
- allow borrower to withdraw backing while B custodies NFT;
- permit B to seize creditor funds before due date / without funding;
- duplicate repayment and liquidation payouts;
- render honest A's existing release claim impossible after honest B settlement;
- admit unauthenticated NFT deployments through the gate.

Future work: independent economic shadow-ledger invariants spanning `nft`, A, B and credits, malicious NFT callback and unavailable-ETH-recipient probes, stronger proof of canonical gate provenance, and a separate OECL witness that recognizes the **partitioned executable-claim** capability without conflating it with strict whole-token burn redemption.

## Reproduction

```bash
forge test --match-contract OECLPartitionedReserveV3Test -vv
forge test
npm test
```

Do not merge until the exact latest commit passes Hardhat and Foundry in CI and a separate adversarial security review has examined all new authority paths.
