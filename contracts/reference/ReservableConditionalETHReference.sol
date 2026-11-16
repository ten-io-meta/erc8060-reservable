// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../IERC8060Reservable.sol";
import "./IERC721ValueReference.sol";

/// @notice Experimental ETH-backed reservation profile, NOT strict ERC-8060.
/// @dev Active locks can block redemption; this contract does NOT advertise
///      IERC721ValueReference in ERC-165. Never represent it as strict ERC-8060.
///      Not audited or suitable for custody of production funds.
contract ReservableConditionalETHReference is ERC721, ReentrancyGuard, IERC8060Reservable {
    address private constant ETH_ASSET = address(0);

    struct Reservation {
        uint256 approved;
        uint256 locked;
        uint256 epoch;
    }

    uint256 public nextTokenId = 1;
    uint256 public totalBacked;

    mapping(uint256 => uint256) private _backing;
    mapping(uint256 => uint256) private _locked;
    mapping(uint256 => uint256) private _approvalEpoch;
    mapping(uint256 => mapping(address => Reservation)) private _reservations;

    event ETHBackedMint(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event ETHDeposited(uint256 indexed tokenId, uint256 amount);
    event ETHWithdrawn(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event ETHRedeemed(uint256 indexed tokenId, address indexed owner, uint256 amount);

    constructor() ERC721("Reservable Conditional ETH Reference", "RCETH") {}

    function mint() external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value > 0, "zero ETH");
        tokenId = nextTokenId++;
        _backing[tokenId] = msg.value;
        totalBacked += msg.value;
        _safeMint(msg.sender, tokenId);
        emit ETHBackedMint(tokenId, msg.sender, msg.value);
    }

    /// @notice Add real ETH backing. Only current NFT owner can do so.
    function deposit(uint256 tokenId) external payable nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(msg.value > 0, "zero ETH");
        _backing[tokenId] += msg.value;
        totalBacked += msg.value;
        emit ETHDeposited(tokenId, msg.value);
    }

    function backingOf(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "nonexistent token");
        return _backing[tokenId];
    }

    function approveReserve(
        uint256 tokenId, address spender, address asset, uint256 amount
    ) external override {
        _checkLiveAsset(tokenId, asset);
        require(ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(spender != address(0), "invalid spender");
        Reservation storage r = _reservations[tokenId][spender];
        r.approved = amount;
        r.epoch = _approvalEpoch[tokenId];
        emit ReserveApproval(tokenId, spender, asset, amount);
    }

    function reserveAllowance(
        uint256 tokenId, address spender, address asset
    ) public view override returns (uint256) {
        _checkLiveAsset(tokenId, asset);
        Reservation storage r = _reservations[tokenId][spender];
        if (r.epoch != _approvalEpoch[tokenId] || r.approved <= r.locked) return 0;
        return r.approved - r.locked;
    }

    function reserveValue(
        uint256 tokenId, address asset, uint256 amount
    ) external override {
        _checkLiveAsset(tokenId, asset);
        require(amount > 0, "zero amount");
        require(amount <= reserveAllowance(tokenId, msg.sender, asset), "insufficient reserve allowance");
        require(amount <= availableValue(tokenId, asset), "insufficient available");
        Reservation storage r = _reservations[tokenId][msg.sender];
        r.locked += amount;
        _locked[tokenId] += amount;
        emit ValueReserved(tokenId, msg.sender, asset, amount);
    }

    function releaseValue(
        uint256 tokenId, address asset, uint256 amount
    ) external override {
        _checkLiveAsset(tokenId, asset);
        require(amount > 0, "zero amount");
        Reservation storage r = _reservations[tokenId][msg.sender];
        require(amount <= r.locked, "release exceeds allocation");
        r.locked -= amount;
        _locked[tokenId] -= amount;
        emit ValueReleased(tokenId, msg.sender, asset, amount);
    }

    function lockedValue(
        uint256 tokenId, address asset
    ) public view override returns (uint256) {
        _checkLiveAsset(tokenId, asset);
        return _locked[tokenId];
    }

    function availableValue(
        uint256 tokenId, address asset
    ) public view override returns (uint256) {
        _checkLiveAsset(tokenId, asset);
        return _backing[tokenId] - _locked[tokenId];
    }

    /// @notice Partial withdrawal only from unreserved ETH; this is NOT ERC-8060 burn.
    function withdrawAvailable(uint256 tokenId, uint256 amount) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(amount > 0 && amount <= availableValue(tokenId, ETH_ASSET), "insufficient available");
        _backing[tokenId] -= amount;
        totalBacked -= amount;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "ETH withdrawal failed");
        emit ETHWithdrawn(tokenId, msg.sender, amount);
    }

    /// @notice Nonstandard terminal redemption, only after all locks have gone.
    function redeemWhenUnlocked(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(_locked[tokenId] == 0, "active reservation blocks redemption");
        uint256 payout = _backing[tokenId];
        delete _backing[tokenId];
        totalBacked -= payout;
        _burn(tokenId);
        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        require(sent, "ETH redemption failed");
        emit ETHRedeemed(tokenId, msg.sender, payout);
    }

    /// @notice Read-only coverage check; ETH surplus is neither allocatable nor withdrawable.
    function isSolvent() external view returns (bool) {
        return address(this).balance >= totalBacked;
    }

    function _checkLiveAsset(uint256 tokenId, address asset) internal view {
        require(asset == ETH_ASSET, "ETH only");
        require(_exists(tokenId), "nonexistent token");
    }

    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        if (from != address(0) && to != address(0) && from != to) {
            _approvalEpoch[firstTokenId] += 1;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721) returns (bool)
    {
        if (interfaceId == type(IERC721ValueReference).interfaceId) return false;
        return interfaceId == type(IERC8060Reservable).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
