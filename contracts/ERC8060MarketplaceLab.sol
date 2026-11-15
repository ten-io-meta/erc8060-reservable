// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IERC8060Reservable.sol";

/// @notice Laboratory-only value query. In a CONDITIONAL profile, valueOf
///         is NOT standardized by IERC8060Reservable; this is a known adapter
///         for ERC8060ConditionalProfileLab, NOT a general market interface.
interface IValueOfMarketplaceLab {
    function valueOf(uint256 tokenId) external view returns (uint256);
}

interface IERC165MarketplaceLab {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice Experimental listing and atomic settlement; not audited or production-ready.
/// @dev buyNaive is intentionally unsafe to reproduce the stale-quote issue.
contract ERC8060MarketplaceLab is ReentrancyGuard {
    bytes4 private constant ERC8060_INTERFACE_ID = 0x88495fe7;
    address private constant ETH_ASSET = address(0);

    struct Listing { address seller; uint256 price; }
    mapping(address => mapping(uint256 => Listing)) public listings;

    event Listed(address indexed nft, uint256 indexed tokenId, address indexed seller, uint256 price);
    event Purchased(address indexed nft, uint256 indexed tokenId, address indexed buyer, uint256 price);

    function list(address nft, uint256 tokenId, uint256 price) external {
        require(nft != address(0), "zero NFT");
        require(price > 0, "zero price");
        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "not owner");
        listings[nft][tokenId] = Listing(msg.sender, price);
        emit Listed(nft, tokenId, msg.sender, price);
    }

    /// @notice KNOWN-VULNERABLE EXAMPLE: ignores locked collateral entirely.
    function buyNaive(address nft, uint256 tokenId) external payable nonReentrant {
        Listing memory listing = _checkListing(nft, tokenId);
        _settle(nft, tokenId, listing);
    }

    /// @notice Accept only NFTs that advertise the strict draft ERC-8060 ID.
    /// @dev Buyer supplies minBacking; checked in this settlement transaction.
    function buyStrict(address nft, uint256 tokenId, uint256 minBacking)
        external payable nonReentrant
    {
        Listing memory listing = _checkListing(nft, tokenId);
        require(
            IERC165MarketplaceLab(nft).supportsInterface(ERC8060_INTERFACE_ID),
            "not strict ERC8060"
        );
        require(IValueOfMarketplaceLab(nft).valueOf(tokenId) >= minBacking, "backing below minimum");
        _settle(nft, tokenId, listing);
    }

    /// @notice LAB-SPECIFIC adapter for the CONDITIONAL profile under test.
    /// @dev IERC8060Reservable alone does NOT standardize valueOf or a
    ///      guarantee that zero locked ETH implies burn will succeed.
    function buyConditionalLab(address nft, uint256 tokenId, uint256 minBacking)
        external payable nonReentrant
    {
        Listing memory listing = _checkListing(nft, tokenId);
        IERC165MarketplaceLab detector = IERC165MarketplaceLab(nft);
        require(!detector.supportsInterface(ERC8060_INTERFACE_ID), "use strict purchase");
        require(
            detector.supportsInterface(type(IERC8060Reservable).interfaceId),
            "not reservable"
        );
        require(
            IERC8060Reservable(nft).lockedValue(tokenId, ETH_ASSET) == 0,
            "reservation blocks redemption"
        );
        require(IValueOfMarketplaceLab(nft).valueOf(tokenId) >= minBacking, "backing below minimum");
        _settle(nft, tokenId, listing);
    }

    function _checkListing(address nft, uint256 tokenId) internal view returns (Listing memory l) {
        l = listings[nft][tokenId];
        require(l.seller != address(0), "not listed");
        require(msg.value == l.price, "wrong payment");
        require(IERC721(nft).ownerOf(tokenId) == l.seller, "seller no longer owner");
    }

    function _settle(address nft, uint256 tokenId, Listing memory l) internal {
        delete listings[nft][tokenId];
        IERC721(nft).safeTransferFrom(l.seller, msg.sender, tokenId);
        (bool paid, ) = payable(l.seller).call{value: l.price}("");
        require(paid, "seller payment failed");
        emit Purchased(nft, tokenId, msg.sender, l.price);
    }
}
