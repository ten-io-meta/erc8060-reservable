// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/reference/ReservableConditionalETHReference.sol";
import "../contracts/BilateralTimeboundReserve.sol";
import "../contracts/ReservableRepaymentLoanDemo.sol";
import "../contracts/CustodiedCollateralLoanPoC.sol";

/// @notice OECL economic composition experiment 1.
/// Two independent application contracts interact with ONE real-ETH-backed token.
/// An accounting-safe composition can still lack an executable creditor remedy.
/// This is evidence of a semantic boundary, NOT a vulnerability in the six
/// IERC8060Reservable accounting functions and NOT a production integration.
contract EconomicCompositionV1Test is Test {
    ReservableConditionalETHReference internal nft;
    BilateralTimeboundReserve internal appA;
    ReservableRepaymentLoanDemo internal appB;

    address internal constant ETH_ASSET = address(0);
    address internal borrower = address(0xB001);
    address internal lender = address(0x1E0D);
    address internal beneficiary = address(0xBEEF);
    address internal buyer = address(0xB0B);

    bytes32 internal constant TERMS = keccak256("OECL-v1-escrow-accounting-only");

    function setUp() public {
        nft = new ReservableConditionalETHReference();
        appA = new BilateralTimeboundReserve(address(nft));
        appB = new ReservableRepaymentLoanDemo(address(nft));

        vm.deal(borrower, 100 ether);
        vm.deal(lender, 100 ether);
        vm.deal(beneficiary, 100 ether);
        vm.deal(buyer, 100 ether);

        vm.prank(borrower);
        uint256 tokenId = nft.mint{value: 2 ether}();
        assertEq(tokenId, 1, "unexpected minted ID");
        _assertAccounting(0, 2 ether);
    }

    function _proposeAndAcceptA(uint256 amount, uint64 expiry) internal returns (uint256 id) {
        vm.prank(borrower);
        nft.approveReserve(1, address(appA), ETH_ASSET, amount);
        vm.prank(borrower);
        id = appA.propose(1, amount, beneficiary, expiry, TERMS);
        vm.prank(beneficiary);
        appA.accept(id, TERMS);
    }

    function _openAndFundB(
        uint256 collateral,
        uint256 principal,
        uint64 deadline
    ) internal returns (uint256 id) {
        vm.prank(borrower);
        nft.approveReserve(1, address(appB), ETH_ASSET, collateral);
        vm.prank(borrower);
        id = appB.createLoan(1, collateral, principal, lender, deadline);
        vm.prank(lender);
        appB.fundLoan{value: principal}(id);
    }

    function _assertAccounting(uint256 locked, uint256 available) internal view {
        assertEq(nft.backingOf(1), locked + available, "per-token accounting");
        assertEq(nft.lockedValue(1, ETH_ASSET), locked, "aggregate locked");
        assertEq(nft.availableValue(1, ETH_ASSET), available, "available");
        assertEq(address(nft).balance, nft.totalBacked(), "real ETH vs liabilities");
        assertTrue(nft.isSolvent(), "reference vault insolvency");
    }

    function test_TwoApplicationsComposeAtAccountingLayerAndCanCleanlyExit() public {
        uint64 expiry = uint64(block.timestamp + 5 days);
        uint64 deadline = uint64(block.timestamp + 2 days);
        uint256 agreement = _proposeAndAcceptA(0.6 ether, expiry);
        uint256 loanId = _openAndFundB(1 ether, 1 ether, deadline);

        _assertAccounting(1.6 ether, 0.4 ether);
        assertEq(appB.lenderCredits(lender), 0, "funding is not a repayment");

        // Creditor gets REAL ETH back only because a payer pays, not from the reservation.
        vm.prank(borrower);
        appB.repayLoan{value: 1 ether}(loanId);
        _assertAccounting(0.6 ether, 1.4 ether);
        assertEq(appB.lenderCredits(lender), 1 ether, "repayment is backed");

        vm.prank(beneficiary);
        appA.releaseEarly(agreement);
        _assertAccounting(0, 2 ether);
        uint256 lenderBefore = lender.balance;
        vm.prank(lender);
        appB.withdrawRepayment();
        assertEq(lender.balance, lenderBefore + 1 ether, "withdrawal of actual repayment");

        uint256 ownerBefore = borrower.balance;
        vm.prank(borrower);
        nft.redeemWhenUnlocked(1);
        assertEq(borrower.balance, ownerBefore + 2 ether, "final redemption");
        assertEq(address(nft).balance, 0, "all backing paid out");
        assertEq(nft.totalBacked(), 0, "no residual liability");
    }

    function test_CompetingApplicationsCannotReserveMoreThanRealBacking() public {
        _proposeAndAcceptA(0.6 ether, uint64(block.timestamp + 5 days));
        vm.prank(borrower);
        nft.approveReserve(1, address(appB), ETH_ASSET, 1.5 ether);

        vm.startPrank(borrower);
        vm.expectRevert(bytes("insufficient available"));
        appB.createLoan(1, 1.5 ether, 1 ether, lender, uint64(block.timestamp + 2 days));
        vm.stopPrank();

        _assertAccounting(0.6 ether, 1.4 ether);
        assertEq(appB.nextId(), 0, "failed second application must not create claim");
    }

    function test_AccountingSafeButDefaultedLoanHasNoEnforceableClaimPath() public {
        uint64 expiry = uint64(block.timestamp + 5 days);
        uint64 loanDeadline = uint64(block.timestamp + 2 days);
        uint256 agreement = _proposeAndAcceptA(0.6 ether, expiry);
        uint256 loanId = _openAndFundB(1 ether, 1 ether, loanDeadline);

        // Full solvency + disjoint locks do NOT imply creditor recovery at deadline.
        vm.warp(uint256(loanDeadline) + 1);
        _assertAccounting(1.6 ether, 0.4 ether);
        assertEq(appB.lenderCredits(lender), 0, "no ETH credited at default");
        (, , , , , , , bool funded, bool repaid, bool cancelled) = appB.loans(loanId);
        assertTrue(funded && !repaid && !cancelled, "loan still outstanding");

        vm.startPrank(lender);
        vm.expectRevert(bytes("release exceeds allocation"));
        nft.releaseValue(1, ETH_ASSET, 1 ether);
        vm.expectRevert(bytes("not NFT owner"));
        nft.withdrawAvailable(1, 1 ether);
        vm.stopPrank();

        // The owner can withdraw only unreserved ETH; both locks remain intact.
        vm.prank(borrower);
        nft.withdrawAvailable(1, 0.4 ether);
        _assertAccounting(1.6 ether, 0);
        assertEq(appB.lenderCredits(lender), 0, "no foreclosure despite funded debt");

        // A expires correctly; B still has a lock, but no foreclosure path.
        vm.warp(uint256(expiry) + 1);
        appA.releaseExpired(agreement);
        _assertAccounting(1 ether, 0.6 ether);
        assertEq(appB.lenderCredits(lender), 0, "expiry of A does not pay B");
        vm.startPrank(borrower);
        vm.expectRevert(bytes("active reservation blocks redemption"));
        nft.redeemWhenUnlocked(1);
        vm.stopPrank();
    }

    function test_EncumberedNFTTransferPreservesAllLocksButDoesNotCreateCreditorExecution() public {
        _proposeAndAcceptA(0.6 ether, uint64(block.timestamp + 5 days));
        _openAndFundB(1 ether, 1 ether, uint64(block.timestamp + 2 days));

        vm.prank(borrower);
        nft.transferFrom(borrower, buyer, 1);
        assertEq(nft.ownerOf(1), buyer);
        _assertAccounting(1.6 ether, 0.4 ether);

        vm.startPrank(buyer);
        nft.approveReserve(1, address(appA), ETH_ASSET, 0);
        nft.approveReserve(1, address(appB), ETH_ASSET, 0);
        vm.expectRevert(bytes("release exceeds allocation"));
        nft.releaseValue(1, ETH_ASSET, 0.6 ether);
        vm.expectRevert(bytes("active reservation blocks redemption"));
        nft.redeemWhenUnlocked(1);
        vm.stopPrank();

        _assertAccounting(1.6 ether, 0.4 ether);
        assertEq(appB.lenderCredits(lender), 0);
    }

    function test_StrictCustodyLoanRejectsTheConditionalReservationProfile() public {
        // The existing executable-liquidation loan is a DIFFERENT NFT profile.
        // A valid reservable lock cannot be naively plugged into its burn path.
        vm.expectRevert(bytes("untrusted NFT bytecode"));
        new CustodiedCollateralLoanPoC(address(nft));
        _assertAccounting(0, 2 ether);
    }

    function testFuzz_TwoApplicationsPreserveBackingAndNoOvercommitment(
        uint96 alphaSeed,
        uint96 betaSeed
    ) public {
        uint256 alpha = 1 + uint256(alphaSeed) % (1 ether);
        uint256 beta = 1 + uint256(betaSeed) % (2 ether - alpha);
        _proposeAndAcceptA(alpha, uint64(block.timestamp + 5 days));
        _openAndFundB(beta, 0.1 ether, uint64(block.timestamp + 2 days));
        _assertAccounting(alpha + beta, 2 ether - alpha - beta);

        vm.startPrank(borrower);
        vm.expectRevert(bytes("insufficient available"));
        nft.withdrawAvailable(1, 2 ether - alpha - beta + 1);
        vm.stopPrank();
        assertEq(appB.lenderCredits(lender), 0, "locks are not creditor receipts");
    }
}
