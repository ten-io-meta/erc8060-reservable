// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IAdversarialMintTarget {
    function mint() external payable returns (uint256);
}

/// @notice Local-only ERC721 receiver probing callback reentrancy during
///         _safeMint and during the actual outgoing ETH redemption call.
contract ETHReentrancyProbe is IERC721Receiver {
    address public target;
    bool public conditional;
    uint256 public duringPaymentTargetId;
    bool public mintReentryBlocked;
    bool public paymentReentryBlocked;

    function mintInto(address contractAddress, bool isConditional) external payable {
        target = contractAddress;
        conditional = isConditional;
        IAdversarialMintTarget(contractAddress).mint{value: msg.value}();
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external override returns (bytes4)
    {
        require(msg.sender == target, "not target NFT");
        bytes memory payload = conditional
            ? abi.encodeWithSignature("redeemWhenUnlocked(uint256)", tokenId)
            : abi.encodeWithSignature("burn(uint256)", tokenId);
        (bool ok,) = target.call(payload);
        mintReentryBlocked = !ok;
        return IERC721Receiver.onERC721Received.selector;
    }

    function redeem(uint256 tokenId, uint256 nextTokenToAttack) external {
        duringPaymentTargetId = nextTokenToAttack;
        bytes memory payload = conditional
            ? abi.encodeWithSignature("redeemWhenUnlocked(uint256)", tokenId)
            : abi.encodeWithSignature("burn(uint256)", tokenId);
        (bool ok,) = target.call(payload);
        require(ok, "redeem failed");
        duringPaymentTargetId = 0;
    }

    receive() external payable {
        if (duringPaymentTargetId == 0) return;
        bytes memory payload = conditional
            ? abi.encodeWithSignature("redeemWhenUnlocked(uint256)", duringPaymentTargetId)
            : abi.encodeWithSignature("burn(uint256)", duringPaymentTargetId);
        (bool ok,) = target.call(payload);
        paymentReentryBlocked = !ok;
    }
}
