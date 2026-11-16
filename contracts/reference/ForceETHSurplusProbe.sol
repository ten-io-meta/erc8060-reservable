// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Laboratory-only helper for sending ETH without calling a recipient.
/// @dev SELFDESTRUCT balance transfer behavior is chain-dependent; this tests
///      that unexpected surplus does not increase reported NFT liabilities.
contract ForceETHSurplusProbe {
    constructor() payable {
        require(msg.value > 0, "zero ETH");
    }

    function sendSurplus(address payable recipient) external {
        selfdestruct(recipient);
    }
}
