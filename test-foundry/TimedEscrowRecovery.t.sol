// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/reference/ReservableConditionalETHReference.sol";
import "../contracts/TimedReservableEscrow.sol";

/// @notice End-to-end timeout release with actual local EVM ETH custody.
///         It does not settle a trade or transfer reserved ETH to a buyer.
contract TimedEscrowRecoveryFoundryTest is Test {
    ReservableConditionalETHReference internal nft;
    TimedReservableEscrow internal escrow;

    address internal constant SELLER = address(0xA11CE);
    address internal constant BUYER = address(0xB0B);
    address internal constant THIRD_PARTY = address(0xCAFE);
    address internal constant ETH = address(0);

    function setUp() public {
        nft = new ReservableConditionalETHReference();
        escrow = new TimedReservableEscrow(address(nft));
        vm.deal(SELLER, 100 ether);
    }

    function testFuzz_ExpiryPreservesBackingAndUnlocks(uint96 rawAmount, uint32 rawDuration) public {
        uint256 amount = (uint256(rawAmount) % 1e16) + 1;
        uint256 duration = (uint256(rawDuration) % 100_000) + 1;

        vm.startPrank(SELLER);
        uint256 id = nft.mint{value: amount * 2}();
        nft.approveReserve(id, address(escrow), ETH, amount);
        uint256 escrowId = escrow.createTimedEscrow(id, ETH, amount, SELLER, duration);
        vm.stopPrank();

        assertEq(nft.lockedValue(id, ETH), amount);
        assertEq(nft.availableValue(id, ETH), amount);
        assertEq(nft.totalBacked(), amount * 2);
        assertEq(address(nft).balance, amount * 2);

        vm.expectRevert(bytes("settlement not implemented"));
        escrow.settleTimedEscrow(escrowId);
        assertEq(nft.lockedValue(id, ETH), amount, "unsupported settlement must not unlock");

        // A buyer inherits the active commitment, but not the old owner's
        // unused reserve authorization.
        vm.prank(SELLER);
        nft.transferFrom(SELLER, BUYER, id);
        assertEq(nft.lockedValue(id, ETH), amount);
        assertEq(nft.reserveAllowance(id, address(escrow), ETH), 0);

        vm.expectRevert(bytes("deadline not reached"));
        escrow.refundExpiredEscrow(escrowId);
        vm.warp(block.timestamp + duration);
        vm.expectRevert(bytes("deadline not reached")); // Strictly after the deadline.
        escrow.refundExpiredEscrow(escrowId);

        vm.warp(block.timestamp + 1);
        vm.prank(THIRD_PARTY);
        escrow.refundExpiredEscrow(escrowId);

        assertEq(nft.lockedValue(id, ETH), 0);
        assertEq(nft.availableValue(id, ETH), amount * 2);
        assertEq(nft.totalBacked(), amount * 2);
        assertEq(address(nft).balance, amount * 2);

        vm.expectRevert(bytes("escrow not active"));
        escrow.refundExpiredEscrow(escrowId);

        uint256 beforeBalance = BUYER.balance;
        vm.prank(BUYER);
        nft.redeemWhenUnlocked(id);
        assertEq(BUYER.balance, beforeBalance + amount * 2);
        assertEq(nft.totalBacked(), 0);
        assertEq(address(nft).balance, 0);
    }

    function testFuzz_UnauthorizedCreationCannotReserve(uint96 rawAmount) public {
        uint256 amount = (uint256(rawAmount) % 1e16) + 1;
        vm.prank(SELLER);
        uint256 id = nft.mint{value: amount}();

        vm.expectRevert(bytes("not NFT owner"));
        vm.prank(THIRD_PARTY);
        escrow.createTimedEscrow(id, ETH, amount, SELLER, 100);

        assertEq(nft.lockedValue(id, ETH), 0);
        assertEq(nft.availableValue(id, ETH), amount);
        assertEq(address(nft).balance, amount);
    }
}
