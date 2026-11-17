# OECL v6: adversarial provenance and counterfeit reservation ledger

> **Security research, NOT a production deployment.** No real funds, no `main` updates, no new standard interface. Existing `IERC8060Reservable` core remains six functions.

## Question

Does reading `lockedBy(tokenId,controller,asset)` from an NFT prove that the controller has enforceable ETH collateral **when the NFT implementation or its deployment provenance is adversarial**?

**No.** Direct controller-specific reads are only meaningful **after authenticating the NFT, the factory that registered it, and the factory's true initialization history**. An untrusted NFT can lie; matching runtime bytes can hide forged initial storage.

## Attack 1 — dishonest getter-only NFT

`OECLDishonestReservationNFT` reports:
- `isSolvent() = true`
- `backingOf(1) = 2 ether`
- `lockedValue(1) = 1.8 ether`
- `lockedBy(1, controller) = 1.2 ether`
- `availableValue(1) = 0.2 ether`
- universal ERC165 acceptance.

It actually holds **zero ETH**, unless a third party donates a token amount. A naive reading of its declarations and self-described solvency would accept a fictitious reserve. An authentic gate/factory **must return UNKNOWN**.

Donated ETH does not certify owner-bound redemption or that the declared liabilities are recorded accurately.

## Attack 2 — EXACT reference runtime with counterfeit constructor storage

The `OECLRuntimeStorageForgingHarness` uses a *real EVM contract constructor*. It writes arbitrary initial storage with `SSTORE`, then returns the **exact** runtime code of `ReservableConditionalETHReference`. It is NOT `vm.etch`, `vm.store`, or an onchain ability to edit existing contracts.

The counterfeit collection's deployed `EXTCODEHASH` is exactly the reference's `EXTCODEHASH`. Its constructor-initialized storage reports:
- one token with the borrower's ownership;
- 2 ETH `backingOf`, despite no 2 ETH being deposited;
- 1.2 ETH attributed to another controller via `lockedBy`;
- aggregate reserved 1.2 ETH, available 0.8 ETH;
- `totalBacked = 0` and actual contract ETH balance = 0.

Because `isSolvent()` checks `balance >= totalBacked`, it reports true, even though its per-token claimed backing is fabricated. A withdrawal fails instead of paying real ETH. **Bytecode identity plus a naive solvency getter do not prove correct state initialization or redeemability.**

The test uses a **known storage layout for this exact compiled OpenZeppelin-v4 reference**; it is not intended as a portable layout inference method.

## Attack 3 — forge the factory's registration state with EXACT factory runtime

A second instance of `OECLRuntimeStorageForgingHarness` returns the genuine runtime of `OECLCanonicalAssetFactory` but sets the `assetProfiles[forgedNFT] = 2` mapping entry in its own constructor storage.

The attacker then deploys regular accounting and recovery factories **pointing to the forged factory** and passes their addresses into a regular `OECLCompositionGate` constructor.

All existing gate constructor checks can pass:
- factory codehash matches `type(OECLCanonicalAssetFactory).runtimeCode`;
- other factory codehashes match;
- both application factories point to the presented asset factory.

**Nevertheless the presented registry is not a factory that genuinely created the counterfeit NFT**. A gate constructed from those values may return `ACCEPT` for an accounting surface with fictitious backing.

With the exact-reference-code counterfeit NFT, the partitioned loan's NFT bytecode guard also passes. The loan can take custody of the pre-seeded counterfeit NFT, acquire a new reserve, receive and transfer **real lender ETH**, and appear to the witness as a funded and executable claim after maturity. Its eventual `liquidate()` reverts (the counterfeit vault never received actual backing), leaving the lender with no collateral recovery. This is the decisive failure case **under a malicious trust root**, not a demonstrated vulnerability of a deployment authenticated through the genuine factory.

## Required provenance evidence / operational policy

A safe admission policy must *fail closed* unless its verifier can establish:

1. **Explicitly authenticated trust anchor**: exact expected `chainId`, gate and canonical factory addresses, independent of an applicant's assertions. A bytecode hash cannot identify *which deployment* is genuine.
2. **Construction provenance**: verified deployed *creation transaction / init code* and constructor inputs, or a verified deterministic CREATE2 factory provenance chain; the asset itself must appear in the canonical factory's real created/registered set. Deployed runtime hash alone is insufficient.
3. **Code identity and immutability assumptions**: audited bytecode and no malicious proxy upgrades, delegates or hidden mutability; verify deployment source and any relevant immutables and storage commitments.
4. **Real economic conservation**: onchain backed liabilities, per-token claims and aggregate controller reservations must reconcile against actual held ETH. Do not rely on a sole `isSolvent()` return when that return is computed over fraudulent liabilities. Verify that the trusted implementation genuinely enforces deposits, redemption and controller accounting.
5. **Execution-path evidence**: actual custody, funded live loan, precise `lockedBy` slice, due/grace and a transaction-atomic claim path that pays real ETH. A snapshot or ERC165 flag does not prove the future transaction will succeed.
6. **Evidence reproducibility**: pin a specific implementation compilation, commit/test traces and factory deploy tx/receipt. Treat source publication and EVM testing as *review inputs*, not cryptographic proofs or independent audits.

### Optional pin prototype

`OECLProvenancePin` stores the trusted gate and linked asset factory as immutable constructor-bound references, and rejects a caller's different gate/factory. It is a **policy demonstration**: the constructor input `independentlyAuthenticatedGate` and the pin's own deployment must be independently verified. If an attacker supplies a malicious gate as the trusted input, the pin offers no protection. A pinned reference identity **does not itself certify** economic solvency or arbitrary creditor claims; the verdict `ADMIT_PROFILE` means recognition of a canonical conditional NFT profile under the chosen root only.

The main security difference is `pin(originalGate).inspect(forgedGate, forgedNFT) = UNKNOWN` while the maliciously initialized alternate gate may report ACCEPT.

## Tests and expected results

```bash
forge test --match-contract OECLForgedProvenanceV6Test -vv
forge test
npm test
```

- Blatant liar with no ETH: genuine gate and witness reject as UNKNOWN.
- Authentic NFT codehash + fake owner/backing/locks/solvency storage: genuine gate rejects, despite identical bytecode.
- Authentic factory codehash + fake registration storage: regular gate constructor accepts it, but that gate is **not independently trustworthy**.
- Real-EVM simulated loan funded with ETH against forged storage: untrusted witness can falsely ACCEPT an unenforceable claim; liquidation reverts atomically.
- A pin bound to the genuine root rejects fake gate and fake NFT; a genuinely created NFT is admitted for the bounded **profile** only.
- All earlier invariant suites must remain green, with no changes to the underlying IERC8060Reservable surface.

## Research conclusion

The minimum evidence stack is not just `lockedBy`:

**Verified origin -> authenticated reference implementation and state-transition history -> economically consistent per-controller rights -> executable claim path.**

This demonstrates why OECL must treat **UNKNOWN as a rejection for financial admission** and why proving a specific deployment lineage matters more than recognizing a codehash. No universal permissionless proof of arbitrary contract honesty is claimed.
