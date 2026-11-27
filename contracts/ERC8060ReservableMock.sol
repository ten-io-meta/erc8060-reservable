// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

contract ERC8060ReservableMock is IERC8060Reservable {
    // Test-only identity controls. This host still holds NO ETH.
    address public immutable mockIssuer;
    mapping(uint256 => address) private _owners;
    // Invalidate unused spender permissions in O(1) at every ownership change.
    mapping(uint256 => uint256) private _ownerEpoch;
    mapping(uint256 => mapping(address => uint256)) private _totalValue;
    mapping(uint256 => mapping(address => uint256)) private _lockedValue;

    struct Reservation {
        uint256 approved;
        uint256 locked;
        uint256 approvalEpoch;
    }

    mapping(uint256 => mapping(address => mapping(address => Reservation))) private _reservations;

    constructor() {
        mockIssuer = msg.sender;
        _owners[1] = msg.sender;
    }

    modifier onlyOwner(uint256 tokenId) {
        require(_owners[tokenId] == msg.sender, "not owner");
        _;
    }

    function mintToken(uint256 tokenId, address to) external {
        require(msg.sender == mockIssuer, "not mock issuer");
        require(to != address(0), "invalid recipient");
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = to;
    }

    function mintValue(uint256 tokenId, address asset, uint256 amount) external onlyOwner(tokenId) {
        _totalValue[tokenId][asset] += amount;
    }

    function totalValue(uint256 tokenId, address asset) external view returns (uint256) {
        return _totalValue[tokenId][asset];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "wrong owner");
        require(msg.sender == from, "not authorized");
        require(to != address(0), "invalid recipient");

        // Existing locks remain bound to tokenId and can still be released by
        // their spender. Prior-owner unused allowances are now stale.
        ++_ownerEpoch[tokenId];
        _owners[tokenId] = to;
    }

    function withdraw(uint256 tokenId, address asset, uint256 amount) external onlyOwner(tokenId) {
        require(amount <= availableValue(tokenId, asset), "insufficient available value");
        _totalValue[tokenId][asset] -= amount;
    }

    function approveReserve(
        uint256 tokenId,
        address spender,
        address asset,
        uint256 amount
    ) external onlyOwner(tokenId) {
        Reservation storage r = _reservations[tokenId][spender][asset];
        r.approved = amount;
        r.approvalEpoch = _ownerEpoch[tokenId];
        emit ReserveApproval(tokenId, spender, asset, amount);
    }

    function reserveValue(
        uint256 tokenId,
        address asset,
        uint256 amount
    ) external {
        require(amount > 0, "amount is zero");

        Reservation storage r = _reservations[tokenId][msg.sender][asset];

        require(amount <= reserveAllowance(tokenId, msg.sender, asset), "exceeds reserve allowance");
        require(amount <= availableValue(tokenId, asset), "insufficient available value");

        r.locked += amount;
        _lockedValue[tokenId][asset] += amount;

        emit ValueReserved(tokenId, msg.sender, asset, amount);
    }

    function releaseValue(
        uint256 tokenId,
        address asset,
        uint256 amount
    ) external {
        require(amount > 0, "amount is zero");

        Reservation storage r = _reservations[tokenId][msg.sender][asset];

        require(amount <= r.locked, "release exceeds locked value");

        r.locked -= amount;
        _lockedValue[tokenId][asset] -= amount;

        emit ValueReleased(tokenId, msg.sender, asset, amount);
    }

    function reserveAllowance(
        uint256 tokenId,
        address spender,
        address asset
    ) public view returns (uint256) {
        Reservation memory r = _reservations[tokenId][spender][asset];

        if (r.approvalEpoch != _ownerEpoch[tokenId]) {
            return 0; // Cannot consume unused permission granted by a former owner.
        }

        if (r.approved <= r.locked) {
            return 0;
        }

        return r.approved - r.locked;
    }

    function lockedValue(
        uint256 tokenId,
        address asset
    ) public view returns (uint256) {
        return _lockedValue[tokenId][asset];
    }

    function availableValue(
        uint256 tokenId,
        address asset
    ) public view returns (uint256) {
        return _totalValue[tokenId][asset] - _lockedValue[tokenId][asset];
    }

}