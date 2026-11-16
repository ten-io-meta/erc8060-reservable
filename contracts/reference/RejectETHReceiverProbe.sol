// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IStrictPayableReference {
    function mint() external payable returns (uint256);
    function burn(uint256 tokenId) external;
}

/// @notice Test-only receiver rejecting redemption, to check atomic rollback.
contract RejectETHReceiverProbe is IERC721Receiver {
    function mintInto(address target) external payable {
        IStrictPayableReference(target).mint{value: msg.value}();
    }

    function attemptBurn(address target, uint256 tokenId) external {
        IStrictPayableReference(target).burn(tokenId);
    }

    function onERC721Received(
        address, address, uint256, bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {
        revert("receiver refuses ETH");
    }
}
