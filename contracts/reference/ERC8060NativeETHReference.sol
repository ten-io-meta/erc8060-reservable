// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IERC721ValueReference.sol";

/// @notice Unreviewed reference candidate for STRICT ERC-8060 native-ETH redemption.
/// @dev Each minted NFT has actual ETH deposited into this contract.
///      No partial withdrawal or reservation capability is present.
///      Do not use with real user funds before independent review.
contract ERC8060NativeETHReference is ERC721, ReentrancyGuard, IERC721ValueReference {
    uint256 public nextTokenId = 1;
    uint256 public totalRedeemableValue;

    mapping(uint256 => uint256) private _redeemable;

    event ETHBackedMint(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event ETHRedeemed(uint256 indexed tokenId, address indexed owner, uint256 amount);

    constructor() ERC721("ERC8060 ETH Reference", "E8060") {}

    /// @notice Mints an NFT backed by the exact ETH deposited in this transaction.
    function mint() external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value > 0, "zero ETH");
        tokenId = nextTokenId++;
        _redeemable[tokenId] = msg.value;
        totalRedeemableValue += msg.value;
        _safeMint(msg.sender, tokenId);
        emit ETHBackedMint(tokenId, msg.sender, msg.value);
    }

    function valueOf(uint256 tokenId) public view override returns (uint256) {
        require(_exists(tokenId), "nonexistent token");
        return _redeemable[tokenId];
    }

    /// @notice Only the current owner can destroy the token and receive its ETH.
    function burn(uint256 tokenId) external override nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "not NFT owner");
        uint256 payout = _redeemable[tokenId];

        delete _redeemable[tokenId];
        totalRedeemableValue -= payout;
        _burn(tokenId);

        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        require(sent, "ETH redemption failed");
        emit ETHRedeemed(tokenId, msg.sender, payout);
    }

    /// @notice Read-only custody check; not a proof against adversarial changes.
    function isSolvent() external view returns (bool) {
        return address(this).balance >= totalRedeemableValue;
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721) returns (bool)
    {
        return interfaceId == type(IERC721ValueReference).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
