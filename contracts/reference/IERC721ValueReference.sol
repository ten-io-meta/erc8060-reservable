// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Local interface definition matching the current draft ERC-8060.
/// @dev Defining an interface does not imply ERC approval or a security audit.
interface IERC721ValueReference {
    function valueOf(uint256 tokenId) external view returns (uint256);
    function burn(uint256 tokenId) external;
}
