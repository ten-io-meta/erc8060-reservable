// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/reference/ERC8060NativeETHReference.sol";
import "../contracts/CustodiedCollateralLoanPoC.sol";

/// @notice Fuzz actual ETH flows through a custodied ERC-8060-backed loan.
///         No ERC-8060 Reservable bookkeeping is assumed to transfer value.
contract CustodiedCollateralLoanFoundryTest is Test {
    ERC8060NativeETHReference internal collateral;
    CustodiedCollateralLoanPoC internal loan;

    address internal constant BORROWER = address(0xA11CE);
    address internal constant LENDER = address(0xB0B);
    address internal constant ARBITER = address(0xCAFE);
    address internal constant OUTSIDER = address(0xD00D);
    bytes32 internal constant TERMS = keccak256("consensual loan; fixed payoff; redemption fallback at default");

    function setUp() public {
        vm.deal(BORROWER, 100 ether);
        vm.deal(LENDER, 100 ether);
        vm.deal(OUTSIDER, 100 ether);
        collateral = new ERC8060NativeETHReference();
        loan = new CustodiedCollateralLoanPoC(address(collateral));
    }

    function _propose(uint256 backing, uint256 principal, uint256 payoff)
        internal returns (uint256 id)
    {
        vm.startPrank(BORROWER);
        uint256 nftId = collateral.mint{value: backing}();
        collateral.approve(address(loan), nftId);
        CustodiedCollateralLoanPoC.Offer memory offer = CustodiedCollateralLoanPoC.Offer({
            tokenId: nftId,
            lender: LENDER,
            arbiter: ARBITER,
            principal: principal,
            payoff: payoff,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: uint64(2 days),
            grace: uint64(1 days),
            challenge: uint64(1 days),
            arbitrateFor: uint64(1 days),
            termsHash: TERMS
        });
        id = loan.propose(offer);
        vm.stopPrank();
        assertEq(collateral.ownerOf(nftId), address(loan), "custody must be real");
        assertEq(collateral.valueOf(nftId), backing, "redemption floor unchanged");
    }

    function _fund(uint256 id, uint256 principal) internal {
        uint256 beforeBalance = BORROWER.balance;
        vm.prank(LENDER);
        loan.fund{value: principal}(id, TERMS);
        assertEq(BORROWER.balance, beforeBalance + principal, "actual lender funding to borrower");
        assertEq(address(loan).balance, 0, "principal not held as phantom collateral");
    }

    function testFuzz_DefaultBurnPaysOnlyOutstandingAndReturnsSurplus(
        uint96 backingRaw, uint96 principalRaw, uint96 interestRaw, uint96 partialRaw
    ) public {
        uint256 principal = (uint256(principalRaw) % 1e16) + 1;
        uint256 interest = uint256(interestRaw) % (principal + 1);
        uint256 payoff = principal + interest;
        uint256 surplus = uint256(backingRaw) % 1e16;
        uint256 backing = payoff + surplus;
        uint256 paid = uint256(partialRaw) % payoff; // strictly less than payoff
        uint256 id = _propose(backing, principal, payoff);
        _fund(id, principal);

        if (paid > 0) {
            vm.prank(BORROWER);
            loan.repay{value: paid}(id);
        }
        assertEq(loan.credits(LENDER), paid, "partial repayment creditor credit");
        assertEq(address(loan).balance, paid, "escrow holds only partial repayments");
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.expectRevert(bytes("challenge open"));
        loan.liquidate(id);
        vm.warp(block.timestamp + 2 days);
        vm.prank(OUTSIDER);
        loan.liquidate(id);

        assertEq(collateral.totalRedeemableValue(), 0, "NFT backing burned exactly once");
        assertEq(address(collateral).balance, 0, "original NFT backing moved");
        assertEq(loan.credits(LENDER), payoff, "lender gets paid + recovered remainder");
        assertEq(loan.credits(BORROWER), backing - (payoff - paid), "borrower gets residual ETH");
        assertEq(loan.totalCredits(), paid + backing, "no double-credit");
        assertEq(address(loan).balance, loan.totalCredits(), "real ETH equals all claims");
        vm.expectRevert(bytes("not liquidatable"));
        loan.liquidate(id);

        vm.prank(LENDER);
        loan.withdrawCredit(payable(LENDER));
        uint256 borrowerShare = backing - (payoff - paid);
        if (borrowerShare > 0) {
            vm.prank(BORROWER);
            loan.withdrawCredit(payable(BORROWER));
        } else {
            assertEq(loan.credits(BORROWER), 0, "no invented borrower surplus");
            vm.expectRevert(bytes("no credit"));
            vm.prank(BORROWER);
            loan.withdrawCredit(payable(BORROWER));
        }

        assertEq(address(loan).balance, 0, "all creditor and borrower payouts possible");
        assertEq(loan.totalCredits(), 0, "credits exhausted");
    }

    function testFuzz_FullRepaymentReleasesOnlyAuthenticatedBorrower(uint96 principalRaw, uint96 interestRaw)
        public
    {
        uint256 principal = (uint256(principalRaw) % 1e16) + 1;
        uint256 payoff = principal + (uint256(interestRaw) % (principal + 1));
        uint256 id = _propose(payoff + 1000, principal, payoff);
        _fund(id, principal);

        vm.prank(OUTSIDER);
        loan.repay{value: payoff}(id); // any payer may settle; lender gets credit
        vm.expectRevert(bytes("not borrower"));
        vm.prank(OUTSIDER);
        loan.claimCollateral(id, OUTSIDER);
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);
        assertEq(collateral.ownerOf(1), BORROWER);
        assertEq(loan.credits(LENDER), payoff);
        assertEq(address(collateral).balance, payoff + 1000);
        vm.expectRevert(bytes("not active"));
        loan.declareDefault(id);
    }

    function test_ArbitrationForgivenessNeedsNamedResolverAndDoesNotPayFromNFT() public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);

        vm.expectRevert(bytes("not arbiter"));
        vm.prank(OUTSIDER);
        loan.arbitrate(id, true);
        vm.prank(ARBITER);
        loan.arbitrate(id, true);
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);

        assertEq(collateral.ownerOf(1), BORROWER, "trusted arbitrator returns NFT");
        assertEq(loan.credits(LENDER), 0, "offchain relief does not fabricate payment");
        assertEq(address(collateral).balance, 2 ether, "no unintended collateral burn");
    }

    function test_ArbitrationTimeoutHasDeterministicDefaultNotEternalLock() public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);
        vm.expectRevert(bytes("arbitration open"));
        loan.liquidate(id);
        vm.warp(block.timestamp + 3 days);
        vm.prank(OUTSIDER);
        loan.liquidate(id);
        assertEq(loan.credits(LENDER), 1.1 ether);
        assertEq(loan.credits(BORROWER), 0.9 ether);
    }

    function test_OneNFTCannotSecureMultipleConcurrentLoans() public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        vm.expectRevert();
        vm.prank(BORROWER);
        collateral.transferFrom(BORROWER, OUTSIDER, 1);
        vm.prank(BORROWER);
        loan.cancelUnfunded(id, BORROWER);
        assertEq(collateral.ownerOf(1), BORROWER);
        assertEq(address(loan).balance, 0);
    }
}
