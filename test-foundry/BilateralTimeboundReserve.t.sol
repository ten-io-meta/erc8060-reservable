// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/reference/ReservableConditionalETHReference.sol";
import "../contracts/BilateralTimeboundReserve.sol";

/// @notice Bounded two-party commitments: release requires either beneficiary
///         authorization or the deadline that BOTH sides agreed before lock.
contract BilateralTimeboundReserveFoundryTest is Test {
    ReservableConditionalETHReference internal nft;
    BilateralTimeboundReserve internal terms;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCAFE);
    address internal constant ETH = address(0);
    bytes32 internal constant TERMS = keccak256("demo: reservation ends unconditionally at expiry; no settlement");
    bytes32 internal constant WRONG = keccak256("other document");

    function setUp() public {
        nft = new ReservableConditionalETHReference();
        terms = new BilateralTimeboundReserve(address(nft));
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
    }

    function _propose(uint256 tokenId, uint256 amount, address beneficiary, uint64 deadline)
        internal returns (uint256 agreementId)
    {
        vm.prank(ALICE);
        agreementId = terms.propose(tokenId, amount, beneficiary, deadline, TERMS);
    }

    function _mint(uint256 amount) internal returns (uint256 id) {
        vm.prank(ALICE);
        id = nft.mint{value: amount}();
    }

    function _approve(uint256 tokenId, uint256 ceiling) internal {
        vm.prank(ALICE);
        nft.approveReserve(tokenId, address(terms), ETH, ceiling);
    }

    function _accept(uint256 agreementId) internal {
        vm.prank(BOB);
        terms.accept(agreementId, TERMS);
    }

    function testFuzz_ConsentOwnerCannotCancelAndAnyCallerCanReleaseAfterExpiry(
        uint96 rawAmount, uint32 rawDuration
    ) public {
        uint256 amount = (uint256(rawAmount) % 1e16) + 1;
        uint256 duration = (uint256(rawDuration) % 30 days) + 1;
        uint64 deadline = uint64(block.timestamp + duration);
        uint256 tokenId = _mint(amount * 2);
        _approve(tokenId, amount);
        uint256 id = _propose(tokenId, amount, BOB, deadline);

        // Before acceptance owner can cancel, but cannot bind beneficiary.
        vm.expectRevert(bytes("not beneficiary"));
        vm.prank(ALICE);
        terms.accept(id, TERMS);
        vm.expectRevert(bytes("terms mismatch"));
        vm.prank(BOB);
        terms.accept(id, WRONG);
        assertEq(nft.lockedValue(tokenId, ETH), 0);

        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), amount);
        assertEq(nft.availableValue(tokenId, ETH), amount);

        vm.expectRevert(bytes("not proposed")); // Neither side can cancel an active commitment.
        vm.prank(ALICE);
        terms.cancelPending(id);
        vm.expectRevert(bytes("not beneficiary"));
        vm.prank(ALICE);
        terms.releaseEarly(id);
        vm.expectRevert(bytes("not beneficiary"));
        vm.prank(CAROL);
        terms.releaseEarly(id);
        vm.expectRevert(bytes("deadline not reached"));
        vm.prank(ALICE);
        terms.releaseExpired(id);
        vm.expectRevert(bytes("active reservation blocks redemption"));
        vm.prank(ALICE);
        nft.redeemWhenUnlocked(tokenId);

        // Transfer never erases the previously accepted lock.
        vm.prank(ALICE);
        nft.transferFrom(ALICE, CAROL, tokenId);
        assertEq(nft.lockedValue(tokenId, ETH), amount);
        vm.expectRevert(bytes("release exceeds allocation"));
        vm.prank(CAROL);
        nft.releaseValue(tokenId, ETH, amount);

        vm.warp(deadline - 1);
        vm.expectRevert(bytes("deadline not reached"));
        terms.releaseExpired(id);

        vm.warp(deadline);
        vm.prank(CAROL);
        terms.releaseExpired(id); // Anyone, including the current owner, may execute at expiry.

        assertEq(nft.lockedValue(tokenId, ETH), 0);
        assertEq(nft.availableValue(tokenId, ETH), amount * 2);
        assertEq(nft.totalBacked(), amount * 2);
        assertEq(address(nft).balance, amount * 2);

        vm.expectRevert(bytes("not active"));
        terms.releaseExpired(id);

        uint256 beforeETH = CAROL.balance;
        vm.prank(CAROL);
        nft.redeemWhenUnlocked(tokenId);
        assertEq(CAROL.balance, beforeETH + amount * 2);
        assertEq(nft.totalBacked(), 0);
        assertEq(address(nft).balance, 0);
    }

    function testFuzz_BeneficiaryEarlyReleaseIsOnlyAuthorizedPreExpiry(uint96 rawAmount) public {
        uint256 amount = (uint256(rawAmount) % 1e16) + 1;
        uint256 tokenId = _mint(amount);
        _approve(tokenId, amount);
        uint256 id = _propose(tokenId, amount, BOB, uint64(block.timestamp + 100 days));
        _accept(id);
        vm.expectRevert(bytes("not beneficiary"));
        vm.prank(ALICE);
        terms.releaseEarly(id);
        vm.prank(BOB);
        terms.releaseEarly(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
        vm.expectRevert(bytes("not active"));
        vm.prank(BOB);
        terms.releaseEarly(id);
        uint256 before = ALICE.balance;
        vm.prank(ALICE);
        nft.redeemWhenUnlocked(tokenId);
        assertEq(ALICE.balance, before + amount);
    }

    function testFuzz_OwnerCannotBindBeneficiaryWithoutApprovedETH(uint96 rawAmount) public {
        uint256 amount = (uint256(rawAmount) % 1e16) + 1;
        uint256 tokenId = _mint(amount);
        uint256 id = _propose(tokenId, amount, BOB, uint64(block.timestamp + 7 days));
        vm.expectRevert(bytes("insufficient reserve allowance"));
        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
        _approve(tokenId, amount - 1);
        vm.expectRevert(bytes("insufficient reserve allowance"));
        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
        _approve(tokenId, amount);
        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), amount);
        assertEq(address(nft).balance, amount);
    }

    function test_ProposalCancelledOrRejectedNeverLocks() public {
        uint256 tokenId = _mint(10 ether);
        _approve(tokenId, 10 ether);
        uint64 deadline = uint64(block.timestamp + 30 days);

        uint256 cancelled = _propose(tokenId, 1 ether, BOB, deadline);
        vm.prank(ALICE);
        terms.cancelPending(cancelled);
        vm.expectRevert(bytes("not proposed"));
        _accept(cancelled);

        uint256 declined = _propose(tokenId, 1 ether, BOB, deadline);
        vm.prank(BOB);
        terms.rejectPending(declined);
        vm.expectRevert(bytes("not proposed"));
        _accept(declined);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
        assertEq(address(nft).balance, 10 ether);
    }

    function test_TransferBeforeAcceptanceInvalidatesOriginalOffer() public {
        uint256 tokenId = _mint(1 ether);
        _approve(tokenId, 1 ether);
        uint256 id = _propose(tokenId, 1 ether, BOB, uint64(block.timestamp + 7 days));
        vm.prank(ALICE);
        nft.transferFrom(ALICE, CAROL, tokenId);
        vm.expectRevert(bytes("owner changed"));
        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
    }

    function test_ExpiredOfferCannotBeAccepted() public {
        uint256 tokenId = _mint(1 ether);
        _approve(tokenId, 1 ether);
        uint256 id = _propose(tokenId, 1 ether, BOB, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 1);
        vm.expectRevert(bytes("deadline passed"));
        _accept(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
    }

    function test_MaximumDeadlineAndInvalidTermsAreRejected() public {
        uint256 tokenId = _mint(1 ether);
        vm.expectRevert(bytes("empty terms"));
        vm.prank(ALICE);
        terms.propose(tokenId, 1 ether, BOB, uint64(block.timestamp + 1 days), bytes32(0));

        vm.expectRevert(bytes("invalid beneficiary"));
        vm.prank(ALICE);
        terms.propose(tokenId, 1 ether, ALICE, uint64(block.timestamp + 1 days), TERMS);

        vm.expectRevert(bytes("duration too long"));
        vm.prank(ALICE);
        terms.propose(tokenId, 1 ether, BOB, uint64(block.timestamp + 366 days), TERMS);

        vm.expectRevert(bytes("deadline passed"));
        vm.prank(ALICE);
        terms.propose(tokenId, 1 ether, BOB, uint64(block.timestamp), TERMS);
    }

    function testFuzz_IndependentAgreementsOneEscrowSpenderNeverReleaseEachOthersLock(
        uint64 rawFirst, uint64 rawSecond
    ) public {
        uint256 first = (uint256(rawFirst) % 1e15) + 1;
        uint256 second = (uint256(rawSecond) % 1e15) + 1;
        uint256 tokenId = _mint(first + second);
        _approve(tokenId, first + second);
        uint64 shortDeadline = uint64(block.timestamp + 1 days);
        uint64 longDeadline = uint64(block.timestamp + 2 days);
        uint256 a = _propose(tokenId, first, BOB, shortDeadline);
        uint256 b = _propose(tokenId, second, CAROL, longDeadline);
        _accept(a);
        vm.prank(CAROL);
        terms.accept(b, TERMS);
        assertEq(nft.lockedValue(tokenId, ETH), first + second);
        vm.warp(shortDeadline);
        terms.releaseExpired(a);
        assertEq(nft.lockedValue(tokenId, ETH), second);
        vm.expectRevert(bytes("active reservation blocks redemption"));
        vm.prank(ALICE);
        nft.redeemWhenUnlocked(tokenId);
        vm.warp(longDeadline);
        terms.releaseExpired(b);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
        assertEq(address(nft).balance, first + second);
    }

    function test_AcceptedDeadlineCannotBeUnilaterallyExtendedOrRevoked() public {
        uint256 tokenId = _mint(10 ether);
        _approve(tokenId, 10 ether);
        uint64 deadline = uint64(block.timestamp + 30 days);
        uint256 id = _propose(tokenId, 8 ether, BOB, deadline);
        _accept(id);

        vm.prank(ALICE);
        nft.approveReserve(tokenId, address(terms), ETH, 0); // revokes future room ONLY
        assertEq(nft.lockedValue(tokenId, ETH), 8 ether);
        assertEq(nft.availableValue(tokenId, ETH), 2 ether);
        vm.expectRevert(bytes("insufficient available"));
        vm.prank(ALICE);
        nft.withdrawAvailable(tokenId, 3 ether);

        // Changes to an entirely new proposal cannot amend the accepted one.
        uint256 newer = _propose(tokenId, 1 ether, CAROL, uint64(block.timestamp + 365 days));
        vm.expectRevert(bytes("insufficient reserve allowance"));
        vm.prank(CAROL);
        terms.accept(newer, TERMS);

        vm.warp(deadline);
        terms.releaseExpired(id);
        assertEq(nft.lockedValue(tokenId, ETH), 0);
    }
}
