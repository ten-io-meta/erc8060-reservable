// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OECLCompositionGate.sol";

/// @title OECLProvenancePin
/// @notice EXPERIMENTAL fail-closed policy for a particular externally
///         authenticated OECL gate/factory deployment pair.
/// @dev This is NOT a self-proving factory or security certificate. The
///      caller MUST independently authenticate which exact gate address
///      is accepted, and verify this policy's deployment/constructor values.
///      Pinning a dishonest gate merely pins dishonesty. No admin updates.
contract OECLProvenancePin {
    enum Verdict { UNKNOWN, REJECT, ADMIT_PROFILE }

    OECLCompositionGate public immutable pinnedGate;
    OECLCanonicalAssetFactory public immutable pinnedFactory;

    constructor(address independentlyAuthenticatedGate) {
        require(independentlyAuthenticatedGate != address(0) &&
                independentlyAuthenticatedGate.code.length > 0, "unknown gate");
        pinnedGate = OECLCompositionGate(independentlyAuthenticatedGate);
        pinnedFactory = pinnedGate.assets();
        require(address(pinnedFactory).code.length != 0, "unknown factory");
    }

    /// @notice Recognizes ONLY conditional reference deployment identity,
    /// rather than a generic claim to backing or permission to lend ETH.
    /// A successful verdict does NOT attest per-token backing, debts, or an audit.
    function inspectConditional(address presentedGate, address asset)
        external view returns (Verdict)
    {
        if (presentedGate != address(pinnedGate) ||
            address(pinnedGate.assets()) != address(pinnedFactory)) {
            return Verdict.UNKNOWN;
        }
        if (pinnedFactory.assetProfiles(asset) != 2) {
            return Verdict.UNKNOWN;
        }
        if (asset.codehash != keccak256(type(ReservableConditionalETHReference).runtimeCode)) {
            return Verdict.REJECT;
        }
        if (!ReservableConditionalETHReference(asset).isSolvent()) {
            return Verdict.REJECT;
        }
        return Verdict.ADMIT_PROFILE;
    }
}
