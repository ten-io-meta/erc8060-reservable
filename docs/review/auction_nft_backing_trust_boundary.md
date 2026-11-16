# ERC-8060 auction: hostile NFT backing and deployment trust

**Scope:** experimental `CustodiedCollateralLoanPoC`, strict native ETH reference only. NOT audited; never use real funds.

## Exploit reproduced before hardening

An arbitrary ERC-721 contract could implement `ownerOf`, `valueOf` and `burn` while storing **zero** ETH. The loan constructor did not authenticate the collection. A colluding borrower could propose a loan with fictitious 2 ETH backing; the lender could send real principal; a buyer could pay real ETH for the NFT at the Dutch auction even though it was not genuinely redeemable. The full-sale pathway did not verify NFT redemption.

The fallback `burnUnsold` compares actual received ETH with `valueOf`, but this acts only **after an unsuccessful sale** and therefore never protects the buyer of a sold NFT.

## Changes

- The loan constructor rejects collections whose **deployed runtime bytecode hash** differs from the exact non-upgradeable `ERC8060NativeETHReference` built with this source/compiler. This blocks arbitrary ERC-721s, faux `valueOf` functions, proxies and superficial ERC-165 claims.
- Initial NFT solvency check and repeat checks through `_verifiedBacking` require `isSolvent()`, nonzero per-token value, token value not greater than native ETH balance and `totalRedeemableValue()` not less than that token's value.
- Verify backing when proposing, funding, opening sale, purchasing, and burning. The existing genuine strict reference functionality and Dutch auction accounting stay intact.
- New regression cases require a fraudulent NFT to be rejected **at loan deployment**, even if an adversary transfers ETH to the fake collection first. Existing adversarial buyer/reentrancy/race tests must continue to pass.

## Remaining trust boundary — important

**Matching code hash is not a mathematical proof of authentic backing, nor proof of a canonical constructor.** In Ethereum, a malicious deployer can use custom *creation code* that returns the exact expected *runtime code* with noncanonical or adversarially initialized storage. Storage-dependent `valueOf`, `totalRedeemableValue`, `isSolvent`, and even ETH balances therefore do not prove complete allocation of backing across all NFTs unless **deployment provenance and initialization** are trusted.

For an eventual real-money deployment, require an independently vetted canonical collection deployment, ideally created by a **known immutable factory** with provable origin and a separately audited mint/redemption path, or a fixed allowlist of verified canonical collection addresses. Neither an arbitrary user-supplied NFT address nor a user-supplied bytecode hash constitutes proof.

Until provenance is enforced and independently audited, the code-hash guard is **defense in depth / risk reduction**, not a complete trustless solution and not authorization to deploy with user funds.

## Safety / acceptance

No change to `IERC8060Reservable` six-function ABI, `main`, or deployed contracts. PR must remain DRAFT until **Hardhat and Foundry suites pass against the exact latest commit**, review of contract size and unresolved constructor/provenance trust issue is complete.
