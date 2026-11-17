// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IReserveControllerView
/// @notice OPTIONAL read-only evidence surface for an ERC-8060 Reservable implementation.
/// @dev NOT part of IERC8060Reservable's six-function ABI. An ERC-165 claim
///      or an arbitrary contract's response is NOT proof of backing or honesty.
///      The returned amount must derive from the asset's OWN authoritative
///      storage and be assessed under authenticated code and provenance.
interface IReserveControllerView {
    /// @notice Exact currently active reservation attributed to a controller.
    /// @dev This value does not depend on currently remaining reserve approval.
    ///      Old locks remain valid after an NFT changes owners or epochs.
    function lockedBy(uint256 tokenId, address controller, address asset)
        external view returns (uint256);
}
