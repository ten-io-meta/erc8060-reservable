// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IERC8060Reservable.sol";

/// @notice Experimental interface matching the current ERC-8060 draft.
interface IERC721ValueProfileLab {
    function valueOf(uint256 tokenId) external view returns (uint256);
    function burn(uint256 tokenId) external;
}

/// @notice Fully ERC-721/ERC-165-enabled STRICT baseline for local testing only.
/// @dev No reservation capability; 1 ETH stays redeemable while the token exists.
contract ERC8060StrictProfileLab is ERC721, ReentrancyGuard {
    uint256 public constant TOKEN_ID = 1;
    uint256 internal _backing;

    constructor() payable ERC721("ERC8060 Profile Lab", "E8LAB") {
        require(msg.value == 1 ether, "requires exactly 1 ETH");
        _backing = msg.value;
        _mint(msg.sender, TOKEN_ID);
    }

    function valueOf(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "nonexistent token");
        return _backing;
    }

    function burn(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "not token owner");
        _checkBeforeBurn();

        uint256 amount = _backing;
        _backing = 0;
        _burn(tokenId);

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "ETH transfer failed");
    }

    function _checkBeforeBurn() internal view virtual {}

    function supportsInterface(bytes4 interfaceId)
        public view virtual override returns (bool)
    {
        return interfaceId == type(IERC721ValueProfileLab).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

/// @notice Test-only CONDITIONAL profile: reservation may block all-or-nothing burn.
/// @dev It intentionally DOES NOT advertise IERC721Value, because the current
///      strict redemption guarantee may be temporarily unavailable.
///      It still exposes valueOf/burn for the controlled experiment; external
///      integrators MUST NOT infer ERC-8060 compliance from their existence.
contract ERC8060ConditionalProfileLab is ERC8060StrictProfileLab, IERC8060Reservable {
    address private constant ETH_ASSET = address(0);

    uint256 private _locked;
    uint256 private _approvalEpoch;

    struct Reservation {
        uint256 approved;
        uint256 locked;
        uint256 epoch;
    }
    mapping(address => Reservation) private _reservations;

    constructor() payable ERC8060StrictProfileLab() {}

    function totalValue(uint256 tokenId, address asset)
        external view returns (uint256)
    {
        _requireETHAndLive(tokenId, asset);
        return _backing;
    }

    function lockedValue(uint256 tokenId, address asset)
        public view override returns (uint256)
    {
        _requireETHAndLive(tokenId, asset);
        return _locked;
    }

    function availableValue(uint256 tokenId, address asset)
        public view override returns (uint256)
    {
        _requireETHAndLive(tokenId, asset);
        return _backing - _locked;
    }

    function approveReserve(
        uint256 tokenId, address spender, address asset, uint256 amount
    ) external override {
        _requireETHAndLive(tokenId, asset);
        require(ownerOf(tokenId) == msg.sender, "not token owner");
        Reservation storage r = _reservations[spender];
        r.approved = amount;
        r.epoch = _approvalEpoch;
        emit ReserveApproval(tokenId, spender, asset, amount);
    }

    function reserveAllowance(uint256 tokenId, address spender, address asset)
        public view override returns (uint256)
    {
        _requireETHAndLive(tokenId, asset);
        Reservation storage r = _reservations[spender];
        if (r.epoch != _approvalEpoch || r.approved <= r.locked) {
            return 0;
        }
        return r.approved - r.locked;
    }

    function reserveValue(uint256 tokenId, address asset, uint256 amount)
        external override
    {
        _requireETHAndLive(tokenId, asset);
        require(amount > 0, "zero amount");
        require(amount <= reserveAllowance(tokenId, msg.sender, asset), "no allowance");
        require(amount <= availableValue(tokenId, asset), "insufficient available");
        Reservation storage r = _reservations[msg.sender];
        r.locked += amount;
        _locked += amount;
        emit ValueReserved(tokenId, msg.sender, asset, amount);
    }

    function releaseValue(uint256 tokenId, address asset, uint256 amount)
        external override
    {
        _requireETHAndLive(tokenId, asset);
        require(amount > 0, "zero amount");
        Reservation storage r = _reservations[msg.sender];
        require(amount <= r.locked, "exceeds locked");
        r.locked -= amount;
        _locked -= amount;
        emit ValueReleased(tokenId, msg.sender, asset, amount);
    }

    function _requireETHAndLive(uint256 tokenId, address asset) internal view {
        require(asset == ETH_ASSET, "ETH only");
        require(_exists(tokenId), "nonexistent token");
    }

    function _checkBeforeBurn() internal view override {
        require(_locked == 0, "active reservation blocks burn");
    }

    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        if (from != address(0) && to != address(0) && from != to) {
            _approvalEpoch += 1;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        if (interfaceId == type(IERC721ValueProfileLab).interfaceId) return false;
        return interfaceId == type(IERC8060Reservable).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
