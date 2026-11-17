// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice REAL EVM adversarial creation: store arbitrary constructor state
/// and return someone else's genuine Solidity runtime bytecode, byte for byte.
/// No Foundry vm.etch, vm.store or privileged runtime manipulation required.
/// Research-only: never use this as a collateral deployment mechanism.
contract OECLRuntimeStorageForgingHarness {
    constructor(bytes memory targetRuntime, bytes32[] memory keys, bytes32[] memory values) payable {
        require(keys.length == values.length, "storage length mismatch");
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 position = keys[i];
            bytes32 stored = values[i];
            assembly {
                sstore(position, stored)
            }
        }
        assembly {
            return(add(targetRuntime, 0x20), mload(targetRuntime))
        }
    }
}

/// @notice Deliberately DISHONEST NFT. Reports fictitious value/locks/solvency
/// independent of real ETH held. Demonstrates why arbitrary getter responses
/// and ERC165 flags cannot be treated as asset-backed commitments.
contract OECLDishonestReservationNFT {
    uint256 public reportedBacking = 2 ether;
    uint256 public reportedTotalLocked = 1.8 ether;
    uint256 public reportedControllerLocked = 1.2 ether;
    address public claimedController;
    address public claimedOwner;

    constructor(address controller, address owner_) {
        claimedController = controller;
        claimedOwner = owner_;
    }

    function isSolvent() external pure returns (bool) {
        return true;
    }

    function totalBacked() external pure returns (uint256) {
        return 2 ether;
    }

    function backingOf(uint256) external view returns (uint256) {
        return reportedBacking;
    }

    function ownerOf(uint256) external view returns (address) {
        return claimedOwner;
    }

    function lockedValue(uint256, address) external view returns (uint256) {
        return reportedTotalLocked;
    }

    function availableValue(uint256, address) external view returns (uint256) {
        return reportedBacking - reportedTotalLocked;
    }

    function lockedBy(uint256, address controller, address) external view returns (uint256) {
        return controller == claimedController ? reportedControllerLocked : 0;
    }

    function reserveAllowance(uint256, address, address) external pure returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    /// @notice Makes the fake even more persuasive without making its
    /// reported backing genuinely withdrawable or its accounting sound.
    receive() external payable {}
}
