# IERC8060Reservable — Design closure and normative specification candidate

**Status:** Proposed protocol-level design closure; not an audited or ratified standard.
**Scope:** Existing `IERC8060Reservable` ABI. No new methods, no ABI break.
**Basis:** Public `contracts/IERC8060Reservable.sol` and README in `ten-io-meta/erc8060-reservable`; ERC-8060 draft in `ten-io-meta/ERCs/ERCS/erc-8060.md`; 135 locally reported passing Hardhat tests including laboratory and deliberately vulnerable demonstration behaviors. The local experimental files have not been independently inspected in full for this document.

## 1. Purpose and boundaries

`IERC8060Reservable` is an optional accounting primitive for reserving token-associated asset value without transferring NFT ownership or underlying asset custody. It defines **authorization**, **allocation of locked value**, **release**, and **two public accounting views**. It does **not** create a beneficiary's independent claim to payment, transfer reserved funds, settle debts, enforce legal obligations, liquidate collateral, adjudicate disputes, or certify solvency.

The existing six-function, three-event Solidity ABI remains **unchanged**:

```solidity
interface IERC8060Reservable {
    event ReserveApproval(uint256 indexed tokenId, address indexed spender, address indexed asset, uint256 amount);
    event ValueReserved(uint256 indexed tokenId, address indexed spender, address indexed asset, uint256 amount);
    event ValueReleased(uint256 indexed tokenId, address indexed spender, address indexed asset, uint256 amount);

    function approveReserve(uint256 tokenId, address spender, address asset, uint256 amount) external;
    function reserveValue(uint256 tokenId, address asset, uint256 amount) external;
    function releaseValue(uint256 tokenId, address asset, uint256 amount) external;
    function reserveAllowance(uint256 tokenId, address spender, address asset) external view returns (uint256);
    function lockedValue(uint256 tokenId, address asset) external view returns (uint256);
    function availableValue(uint256 tokenId, address asset) external view returns (uint256);
}
```

## 2. Definitions

- `T(tokenId, asset)` is the implementation-defined *accounted total claim/value* of the selected asset associated with a live token. **`totalValue` is not a function defined by ERC-8060 or by this interface.** Implementations MUST document how `T` is derived; an optional `totalValue` view is implementation-specific unless independently standardized.
- `L(tokenId, asset)` is the aggregate active reservation of that asset for that token.
- `L_s(tokenId, spender, asset)` is the portion actively locked by one spender.
- `A(tokenId, spender, asset)` is that spender's current authorization *ceiling on concurrent outstanding locked value*, not an irrevocable obligation, single-use grant, or total lifetime usage cap.
- `availableValue = T - L` is *unreserved accounted value*. It is **not** a guarantee that a partial withdrawal exists, that `burn()` succeeds, or that the underlying assets are solvent.
- `asset == address(0)` designates native ETH where supported. Other asset addresses are permitted by the interface but their custody, transfer, decimal/unit and accounting semantics belong to each implementing profile. ERC-8060 itself standardizes native ETH redemption only.

## 3. Mandatory accounting properties (MUST)

1. For every live token and supported asset, maintain `0 <= L <= T` and report `availableValue == T - L`.
2. Maintain `L == SUM(L_s)` over all active reservation spenders (this need not be publicly enumerable). One spender MUST NOT release or consume another spender's allocation.
3. Only the current NFT owner may call `approveReserve` successfully. Reducing an approval, including setting it to zero, MUST NOT alter an existing active reservation.
4. `reserveAllowance(tokenId, spender, asset)` MUST reflect the spender's remaining effective authorization (for the authorization-ceiling model, `max(A - L_s, 0)`). `reserveValue` MUST revert for zero amount, unauthorized amount or amount greater than `availableValue`.
5. `releaseValue` MUST revert for zero amount or amount greater than the caller's own `L_s`, and MUST decrease both `L_s` and aggregate `L` atomically. Only the address owning the active reservation allocation may exercise this primitive.
6. Operations that decrease the assets underpinning the accounted token value MUST preserve all active locked value. Any proposed withdrawal, internal movement or burn that would violate `L <= T` MUST revert. Accountancy is not proof of actual assets: implementations MUST enforce real custody/solvency in their own asset-specific logic.
7. On NFT transfer, existing `L_s` and `L` MUST remain attached to `tokenId`. All **unused authorizations granted by the previous owner MUST be invalidated**, whether through an epoch/generation or another correct mechanism. New owners may grant new approval; prior committed allocations remain protected. ERC-721 approvals and reservation approvals are separate concepts.
8. State updates and corresponding events MUST describe the same successful transition. Failed transactions MUST leave the complete state unchanged. External token or ETH calls require checks-effects-interactions, reentrancy protection and verified return behavior as applicable.
9. Implementations intended as ERC-721 extensions MUST correctly support ERC-721 and ERC-165 and accurately advertise the `IERC8060Reservable` interface ID. ERC-165 is an interface-discovery mechanism, not a security audit or solvency attestation.

**Approval nuance:** Under the authorization-ceiling model, freeing a reservation can restore unused room within the same approval. A one-time or non-reusable authorization must be enforced explicitly by an application or implementation policy. UI descriptions must not mislabel a reusable ceiling as a one-shot consent.

## 4. Compatibility with strict ERC-8060

The current ERC-8060 draft defines `IERC721Value.valueOf(tokenId)` and `burn(tokenId)` and states that the advertised native ETH value is redeemable on burn at the time of the call. A model where `valueOf()` reports 1 ETH but any live reservation blocks `burn()` **cannot truthfully advertise strict ERC-8060 conformance** for that native ETH claim.

Therefore:

- A token contract with conditional, reservation-blocked ETH redemption MUST NOT advertise the strict `IERC721Value` ERC-165 interface as if its immediate burn promise were guaranteed.
- An ERC-8060-compatible implementation MAY also implement `IERC8060Reservable` if its reservations cannot impede the promised `burn()` redemption (for example, commitments are attached to separate assets or an independent accounting pool). Such assets MUST NOT be double-counted.
- ERC-165 exposes supported interfaces at the *contract* level, not an individual token's current lock state. A separate profile must explicitly describe conditional redemption; legacy ERC-8060 wallets cannot be assumed to understand it.
- Wallets/marketplaces handling conditional tokens SHOULD display **accounted total, locked, available, and burn eligibility distinctly**, and MUST re-check relevant conditions inside the settlement transaction when making enforceable claims. A view call made at listing time cannot substitute for atomic settlement checks.
- `availableValue > 0` does not imply a full burn can be executed. With any outstanding lock, the example implementation blocks the entire burn even though some value remains unreserved.

## 5. Irrecoverable reservations

A reservation can persist indefinitely if its controlling spender becomes inaccessible. The base interface deliberately has **no owner-operated force-release**: this protects commitments from unilateral cancellation. Applications SHOULD adopt their own disclosed recovery rules (beneficiary release, explicitly agreed deadlines, arbitration, recovery trustees, or upgrade controls), and MUST communicate the case in which no recovery is possible. A timeout SHOULD NOT silently erase a legitimate outstanding debt; recovery logic must align with the actual obligation.

## 6. Settlement, collateral and borrower protection — out of core

Applications, not `IERC8060Reservable`, enforce loan funding, repayment, slashing, allocation, auction, settlement and release conditions. Reservation accounting **alone cannot transfer or confiscate committed ETH for a creditor**. This is an intentional boundary, not a missing ABI method.

For an opt-in loan that custodies an ERC-8060 NFT as collateral, an application MAY offer an explicitly agreed fallback: sell the NFT after default and credit the lender the debt, returning the surplus; after an agreed grace period, burn the NFT as a last-resort exit if no sale succeeds. These are *separate custodial mechanisms* and do not exercise `IERC8060Reservable` reservations.

**Risk A — Non-fungible market value.** Native backing is not the NFT's market price. The NFT may trade above the ETH redemption floor; burning destroys this excess economic/cultural value. Fixed-price sale is not price discovery. Terms SHOULD disclose valuation methodology, any auction/market-sale period, the possibility of no buyer, the price floors, the remaining repayment window, and exactly when irreversible burn becomes eligible. Neither a 24-hour grace period nor a backing-based minimum guarantees fair market value.

**Risk B — Specific consent and rights.** Before funding, the actual authorized NFT owner MUST agree on-chain or through a verifiable signature to the specific token, principal, repayment obligations, funding expiry, debt maturity, liquidation conditions, sale price rules, burn authorization (if any), grace period and surplus allocation. Approval to transfer an NFT alone is not unambiguous agreement to burn it. An unfunded offer SHOULD have a cancellation/expiry path. A funded loan MUST NOT be unilaterally cancelled without satisfying the contract's agreed repayment or dispute rules. Clear precedence between late repayment, sale and burn is required because competing transactions may race.

**Risk C — Solvency and actual payment.** `supportsInterface()` and `valueOf()` are assertions made by the contract and do not prove real ETH is available or will be paid. A liquidator MUST verify the actual ETH balance change received from a successful burn, check it against the expected amount and revert atomically upon mismatch; a seller/buyer settlement MUST protect the buyer's enforceable minimum and check it at execution. A vault must be capable of receiving ETH. For pooled or upgradeable designs, external review must check that reported claims across *all* live NFTs remain fully backed, not merely that one `valueOf()` call succeeds. Include adversarial contracts, malicious callbacks, rejected receivers, reentrancy, nonstandard ERC-721 behavior and liquidity/no-buyer tests.

## 7. Publication and implementation status

**Ready to freeze conceptually:** Six-function reservation interface; owner authorization; spender-specific accounting; transfer-persistent locks; invalidation of stale approvals; explicit separation from execution/settlement; distinction between strict ERC-8060 and reservation-conditioned profiles.

**Not yet ready to claim:** Production security, independent audit, formal verification, automatic repayment on default, guaranteed market liquidation, ERC-165 detection as a solvency proof, or seamless interpretation by ERC-8060-only wallets.

**Required publication cleanup:**

1. Update `README.md` from its stated `61 passing tests` to explicitly distinguish *public repository state* from the user's **135 passing local experimental tests** (the latter include intentionally unsafe demo behavior, not 135 security attestations).
2. Correct README's statement that ERC-8060 defines `totalValue`: ERC-8060's current public interface defines only `valueOf` and `burn`. Use `T` or state an implementation-specific `totalValue` view.
3. Mark the publicly available `MinimalReservableEscrow`, `AgentTaskBond`, and `MinimalLendingCollateral` as **INSECURE DEMONSTRATION ONLY**: their unrestricted release/settlement/close paths were reproduced in the local tests. Prefer publishing separate corrected examples over silently changing their behavior.
4. Do not reuse the experimental mock or harness as an audited ERC-721 implementation; validate final reference contracts and exact ERC-165 interface IDs independently.
5. Review transfer-approval semantics, atomic settlement and lender/borrower conditions in any final code; reconcile README claims of 'protocol closure' with the above explicit caveats.

## 8. Final decision

**Freeze `IERC8060Reservable`'s ABI without adding `forceRelease`, `spendReservedValue`, `liquidate`, `deadline`, `slash` or reputation functions.** The invariant/accounting layer is sufficiently delimited for a design candidate. Market guarantees, enforceable claims, recoverability, and redemption profiles are separate opt-in application/profile responsibilities. This is a specification closure decision, **not** a production release, approved ERC status, or security certification.

## 9. Subsequent security hardening (experimental branch)

After the design closure, the three accounting-only example contracts were restricted so only the NFT owner can create new example commitments and only the recorded creator can release those commitments. The misleading `settleEscrow` and `settleTaskBond` paths now revert; no payout is simulated and no reservation is abandoned by a false settlement. `MinimalLendingCollateral.closeLoan` remains **only** a demo release by its recorded borrower; it is *not* a funded debt or a claim that repayment occurred. For an actual funded loan, see the separately modeled `ReservableRepaymentLoanDemo`, subject to its own review and limitations.

The default-by-burn laboratory now has a dedicated `authorizeBurnFallback` consent action by the borrower while the loan is unfunded, separate from authorizing NFT custody. This is an experimental opt-in only; it does not prove enforceability, fair-market valuation or safe production liquidation.

The legacy negative tests were changed to expect unauthorized operations and false settlement to revert. Earlier `135 passing` results refer to the pre-hardening commit `acf39f6`. Final test counts must come from the Hardhat suite for the hardened commit, and CI must pass before merging.

**Remaining limits:** No production audit, no formal verification, no general-purpose beneficiary settlement, no independent proof of solvency and no automatic liquidation right under `IERC8060Reservable`. The six-function interface remains unchanged.
