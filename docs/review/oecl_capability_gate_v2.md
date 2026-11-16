# OECL composition gate v2 — provenance + bounded economic-capability admission

**Research only.** No mainnet assets, production safety claim, standard changes, or completed audit.

## Scope and threat model

This experiment tests the hypothesis that contracts can expose a **restricted, evidence-backed capability admission verdict**. It does **not** claim arbitrary deployed protocols are trustworthy.

`OECLCompositionGate` exposes three verdicts:

- `ACCEPT`: a concrete *structural capability* exists **under the exact registered, canonical-reference code and runtime-state assumptions**. Not a universal safety certificate.
- `REJECT`: a recognized composition lacks the requested structural capability or is incompatible.
- `UNKNOWN`: deployment provenance of the asset or application is unrecognized. Never promote to ACCEPT.

The gate is a **closed-world experimental verifier linked to three non-upgradeable factories**. The first monolithic verifier compiled to **52,053 runtime bytes**, beyond EIP-170's **24,576-byte** limit; the architecture was split so each deployed contract can meet that limit:
- The asset factory uses `new ERC8060NativeETHReference()` / `new ReservableConditionalETHReference()` to run the true constructors and record resulting addresses.
- Separate accounting and recovery factories create the exact `BilateralTimeboundReserve`, `ReservableRepaymentLoanDemo`, and `CustodiedCollateralLoanPoC` contracts and record the asset bound at creation.
- It cannot accept caller-provided third-party code, arbitrary factory signatures, UI claims, ERC165 declarations, user-provided code hashes, or donated ETH as proof of provenance.
- Deployment provenance of **the gate and all three factory addresses** must be independently verified. Their runtime code hashes and cross-factory binding are checked at gate construction but, by themselves, cannot prove their initial storage was not forged. Local acceptance does not establish source/audit quality outside this trusted deployment tree.
- The Foundry regression explicitly checks every factory and the gate fits the EIP-170 maximum runtime size (24,576 bytes). Passing these checks remains necessary, not sufficient, for production.

## Capabilities evaluated (explicitly bounded)

| Capability | Relevant admitted profile | Conditions | NOT asserted |
| --- | --- | --- | --- |
| `ReserveAccounting` | Verified conditional NFT, optionally a factory-created bilateral or repayment-only app | NFT solvent | Beneficiary/creditor has settlement rights |
| `OwnerWithdrawAvailable` | Verified conditional NFT directly | NFT solvent | All locked funds are withdrawable |
| `StrictOwnerBurn` | Verified strict NFT directly | NFT solvent | Arbitrary callers may burn |
| `CreditorCreditUponActualRepayment` | Verified conditional NFT + factory-created repayment demo | Creditor payout is only possible *after* someone pays exact ETH | Unpaid default can be recovered |
| `CreditorDefaultRecoveryPath` | Verified strict NFT + factory-created custodial liquidation | Loan funded and live, collateral held by actual app, current backing covers outstanding debt, credits solvent | Sale price, profit, immediate liquidation, legal enforcement, fully automatic liveness |

`CreditorDefaultRecoveryPath` is a **conditional ability to execute a default/auction/fallback**. Its ACCEPT verdict does not promise repayment regardless of failed calls, block producers, arbitrators, disputed transactions, or market availability. It must not be phrased as a guarantee that debt will certainly be paid.

## Candidate OECL verdict rules

- P-01: No unrecognized collection can receive a positive verdict. Even the identical NFT runtime deployed elsewhere is UNKNOWN, showing code hash alone is insufficient.
- P-02: Unauthorized or unregistered applications remain UNKNOWN. Known application paired with another asset is REJECT.
- P-03: Conditional account-only reserve + repayment demo => ACCEPT accounting / conditional repayment; REJECT default recovery.
- P-04: Strict NFT + custodial loan => REJECT default recovery before real funding; ACCEPT (with conditions) for active funded custody.
- P-05: Verified fallback burn produces real ETH credited to the actual lender and borrower; after terminal liquidation it no longer represents a live recoverable loan.
- P-06: Receipt of an onchain instantaneous assessment has an event log but **does not attest to independently reproduced offchain tests, absence of bugs, future solvency, external audits, or arbitrary compositions**.
- P-07: Native-ETH donation to a fake NFT doesn't make it recognized.

## Evidence layers (avoid conflating)

1. **Provenance evidence:** factory-only creation path for accepted NFTs and applications; the factory deployment root must be independently authenticated.
2. **Capability evidence:** explicit onchain identity, associations, solvency and loan state checked at block execution.
3. **Execution evidence:** Foundry end-to-end traces of real funding, repayment or burn, and ETH credit withdrawals.
4. **Test receipts:** commit SHA and CI workflow logs; these are external reproducible testing evidence. **No onchain transaction can prove that an arbitrary offchain test suite ran honestly.**

The gate's `AssessmentReceipt` event is evidence of a particular onchain *decision*, not a proof that economic safety has been established.

## Remaining limitations

- Trusted, genuinely deployed gate and three factory contracts, plus Solidity-compiled implementations; third-party or adversarial contracts are not admitted by this prototype.
- Exact reference contracts may still contain uncaught flaws. Registration is **not** auditing.
- Static state assessment can go stale between transaction admission and actual settlement; an executing application must re-check its own onchain conditions.
- This does not verify a loan's borrower/lender understanding, contract-encoded policy appropriateness, market liquidity, MEV resistance or liveness guarantees.
- This prototype cannot compose conditional reservations with a strict ERC-8060 burn loan on the **same** token, because those are different value token profiles. Supporting enforceable collateral under concurrent reservations is the next unsolved architecture problem.
- Persistent or forced ETH donations are not a proof of redeemable liabilities; core references still need independent audit and formal security analysis.

## Reproduce

```bash
forge test --match-contract OECLCompositionGateV2Test -vv
forge test
npm test
```

Keep the PR **DRAFT** until both full suites pass at its **exact latest commit** and contract runtime-size checks pass. Do not deploy user funds.
