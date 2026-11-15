// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

/// @notice Local integration test harness only. NOT an ERC-721 production implementation.
/// @dev This deliberately reports total backing through valueOf even while a
///      reservation prevents burn, to reproduce Dmitry's interoperability question.
interface IERC721ValueHarness {
    function valueOf(uint256 tokenId) external view returns (uint256);
    function burn(uint256 tokenId) external;
}

contract ERC8060ReservableBurnHarness is IERC721ValueHarness, IERC8060Reservable {
    uint256 public constant TOKEN_ID = 1;
    address public owner;
    uint256 private _backing;
    uint256 private _locked;
    uint256 private _epoch;

    struct Reservation {
        uint256 approved;
        uint256 locked;
        uint256 epoch;
    }

    mapping(address => Reservation) private _reservations;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    constructor() payable {
        require(msg.value == 1 ether, "fund with exactly 1 ETH");
        owner = msg.sender;
        _backing = msg.value;
        emit Transfer(address(0), msg.sender, TOKEN_ID);
    }

    modifier live(uint256 tokenId) {
        require(tokenId == TOKEN_ID && owner != address(0), "nonexistent token");
        _;
    }

    modifier onlyOwner(uint256 tokenId) {
        require(tokenId == TOKEN_ID && msg.sender == owner, "not token owner");
        _;
    }

    function ownerOf(uint256 tokenId) external view live(tokenId) returns (address) {
        return owner;
    }

    function transferFrom(address from, address to, uint256 tokenId)
        external live(tokenId) onlyOwner(tokenId)
    {
        require(from == owner, "wrong from");
        require(to != address(0), "zero recipient");
        owner = to;
        _epoch += 1; // Invalidate all unused old reserve approvals.
        emit Transfer(from, to, tokenId);
    }

    function valueOf(uint256 tokenId) external view override live(tokenId) returns (uint256) {
        return _backing;
    }

    function totalValue(uint256 tokenId, address asset)
        external view live(tokenId) returns (uint256)
    {
        require(asset == address(0), "ETH only");
        return _backing;
    }

    function lockedValue(uint256 tokenId, address asset)
        public view override live(tokenId) returns (uint256)
    {
        require(asset == address(0), "ETH only");
        return _locked;
    }

    function availableValue(uint256 tokenId, address asset)
        public view override live(tokenId) returns (uint256)
    {
        require(asset == address(0), "ETH only");
        return _backing - _locked;
    }

    function approveReserve(uint256 tokenId, address spender, address asset, uint256 amount)
        external override live(tokenId) onlyOwner(tokenId)
    {
        require(asset == address(0), "ETH only");
        Reservation storage r = _reservations[spender];
        r.approved = amount;
        r.epoch = _epoch;
        emit ReserveApproval(tokenId, spender, asset, amount);
    }

    function reserveAllowance(uint256 tokenId, address spender, address asset)
        public view override live(tokenId) returns (uint256)
    {
        require(asset == address(0), "ETH only");
        Reservation storage r = _reservations[spender];
        if (r.epoch != _epoch || r.approved <= r.locked) return 0;
        return r.approved - r.locked;
    }

    function reserveValue(uint256 tokenId, address asset, uint256 amount)
        external override live(tokenId)
    {
        require(asset == address(0), "ETH only");
        require(amount > 0, "zero amount");
        require(amount <= reserveAllowance(tokenId, msg.sender, asset), "no allowance");
        require(amount <= availableValue(tokenId, asset), "insufficient available");
        _reservations[msg.sender].locked += amount;
        _locked += amount;
        emit ValueReserved(tokenId, msg.sender, asset, amount);
    }

    function releaseValue(uint256 tokenId, address asset, uint256 amount)
        external override live(tokenId)
    {
        require(asset == address(0), "ETH only");
        require(amount > 0, "zero amount");
        Reservation storage r = _reservations[msg.sender];
        require(amount <= r.locked, "exceeds locked");
        r.locked -= amount;
        _locked -= amount;
        emit ValueReleased(tokenId, msg.sender, asset, amount);
    }

    function burn(uint256 tokenId) external override live(tokenId) onlyOwner(tokenId) {
        require(_locked == 0, "active reservation blocks burn");
        uint256 amount = _backing;
        _backing = 0;
        owner = address(0);
        emit Transfer(msg.sender, address(0), tokenId);
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH transfer failed");
    }
}
