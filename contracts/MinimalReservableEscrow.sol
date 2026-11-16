// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

interface IEscrowOwnerView {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice ACCOUNTING-ONLY DEMO, not a production escrow or payout contract.
contract MinimalReservableEscrow {
    IERC8060Reservable public immutable reservable;

    struct Escrow {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address seller;
        bool active;
        bool settled;
    }

    uint256 public nextEscrowId;
    mapping(uint256 => Escrow) public escrows;
    mapping(uint256 => address) public creators;

    event EscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed tokenId,
        address indexed seller,
        address asset,
        uint256 amount
    );

    event EscrowReleased(uint256 indexed escrowId);
    event EscrowSettled(uint256 indexed escrowId);

    constructor(address reservable_) {
        reservable = IERC8060Reservable(reservable_);
    }

    function createEscrow(
        uint256 tokenId,
        address asset,
        uint256 amount,
        address seller
    ) external returns (uint256 escrowId) {
        require(IEscrowOwnerView(address(reservable)).ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(seller != address(0), "invalid seller");
        require(amount > 0, "zero amount");
        reservable.reserveValue(tokenId, asset, amount);

        escrowId = nextEscrowId++;

        creators[escrowId] = msg.sender;
        escrows[escrowId] = Escrow({
            tokenId: tokenId,
            asset: asset,
            amount: amount,
            seller: seller,
            active: true,
            settled: false
        });

        emit EscrowCreated(escrowId, tokenId, seller, asset, amount);
    }

    function releaseEscrow(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];

        require(e.active, "Escrow not active");
        require(!e.settled, "Escrow already settled");
        require(msg.sender == creators[escrowId], "not escrow creator");

        e.active = false;

        reservable.releaseValue(e.tokenId, e.asset, e.amount);

        emit EscrowReleased(escrowId);
    }

    /// @notice No payout implemented; a false settlement would orphan a lock.
    function settleEscrow(uint256) external pure {
        revert("settlement not implemented");
    }
}
