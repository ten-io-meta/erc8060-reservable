// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

interface ITimedEscrowOwnerView {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Accounting-only timed recovery demonstration; NO payment settlement.
contract TimedReservableEscrow {
    IERC8060Reservable public immutable reservable;

    struct TimedEscrow {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address seller;
        uint256 deadline;
        bool active;
        bool settled;
        bool refunded;
    }

    uint256 public nextEscrowId;
    mapping(uint256 => TimedEscrow) public escrows;

    event TimedEscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed tokenId,
        address indexed seller,
        address asset,
        uint256 amount,
        uint256 deadline
    );

    event TimedEscrowSettled(uint256 indexed escrowId);
    event TimedEscrowRefunded(uint256 indexed escrowId);

    constructor(address reservable_) {
        require(reservable_ != address(0), "invalid reservable");
        reservable = IERC8060Reservable(reservable_);
    }

    function createTimedEscrow(
        uint256 tokenId,
        address asset,
        uint256 amount,
        address seller,
        uint256 duration
    ) external returns (uint256 escrowId) {
        require(amount > 0, "amount is zero");
        require(seller != address(0), "invalid seller");
        require(duration > 0, "duration is zero");
        require(ITimedEscrowOwnerView(address(reservable)).ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(seller == msg.sender, "seller must be owner");

        reservable.reserveValue(tokenId, asset, amount);

        escrowId = nextEscrowId++;

        escrows[escrowId] = TimedEscrow({
            tokenId: tokenId,
            asset: asset,
            amount: amount,
            seller: seller,
            deadline: block.timestamp + duration,
            active: true,
            settled: false,
            refunded: false
        });

        emit TimedEscrowCreated(
            escrowId,
            tokenId,
            seller,
            asset,
            amount,
            block.timestamp + duration
        );
    }

    /// @notice Settlement is NOT implemented: no payout may be claimed by any caller.
    /// @dev Revert without changing the lock; the documented timeout refund remains usable.
    function settleTimedEscrow(uint256) external pure {
        revert("settlement not implemented");
    }

    function refundExpiredEscrow(uint256 escrowId) external {
        TimedEscrow storage e = escrows[escrowId];

        require(e.active, "escrow not active");
        require(!e.settled, "escrow settled");
        require(block.timestamp > e.deadline, "deadline not reached");

        e.active = false;
        e.refunded = true;

        reservable.releaseValue(e.tokenId, e.asset, e.amount);

        emit TimedEscrowRefunded(escrowId);
    }
}