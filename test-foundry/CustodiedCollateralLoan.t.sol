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
        vm.deal(ARBITER, 100 ether);
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
            termsHash: TERMS,
            saleStartPrice: uint128(backing * 2),
            saleDuration: uint64(1 hours)
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

    function _openExpireAndBurn(uint256 id) internal {
        loan.startSale(id);
        vm.warp(block.timestamp + 1 hours + 1);
        loan.burnUnsold(id);
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
        loan.startSale(id);
        vm.warp(block.timestamp + 2 days);
        loan.startSale(id);
        vm.expectRevert(bytes("auction still active"));
        loan.burnUnsold(id);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(OUTSIDER);
        loan.burnUnsold(id);

        assertEq(collateral.totalRedeemableValue(), 0, "NFT backing burned exactly once");
        assertEq(address(collateral).balance, 0, "original NFT backing moved");
        assertEq(loan.credits(LENDER), payoff, "lender gets paid + recovered remainder");
        assertEq(loan.credits(BORROWER), backing - (payoff - paid), "borrower gets residual ETH");
        assertEq(loan.totalCredits(), paid + backing, "no double-credit");
        assertEq(address(loan).balance, loan.totalCredits(), "real ETH equals all claims");
        vm.expectRevert(bytes("not sale open"));
        loan.burnUnsold(id);

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

    function test_ArbitrationMayReturnNFTOnlyAfterActualCreditorPayment() public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);

        vm.expectRevert(bytes("not arbiter"));
        vm.prank(OUTSIDER);
        loan.arbitrate(id, true);
        vm.expectRevert(bytes("exact payoff required"));
        vm.prank(ARBITER);
        loan.arbitrate(id, true);
        vm.expectRevert(bytes("exact payoff required"));
        vm.prank(ARBITER);
        loan.arbitrate{value: 1 ether}(id, true);
        vm.expectRevert(bytes("not releasable"));
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);

        vm.prank(ARBITER);
        loan.arbitrate{value: 1.1 ether}(id, true);
        assertEq(loan.credits(LENDER), 1.1 ether, "credit requires real ETH");
        assertEq(address(loan).balance, 1.1 ether, "credit must be funded");
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);
        assertEq(collateral.ownerOf(1), BORROWER, "fully funded dispute settlement returns NFT");
        assertEq(address(collateral).balance, 2 ether, "collateral stays alive after payment");
    }

    function test_ArbitrationTimeoutHasDeterministicDefaultNotEternalLock() public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);
        vm.expectRevert(bytes("arbitration open"));
        loan.startSale(id);
        vm.warp(block.timestamp + 3 days);
        vm.prank(OUTSIDER);
        _openExpireAndBurn(id);
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
    function test_ExactRedemptionFloorLeavesNoFakeBorrowerCredit() public {
        uint256 id = _propose(1, 1, 1);
        _fund(id, 1);
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.warp(block.timestamp + 2 days);
        _openExpireAndBurn(id);

        assertEq(loan.credits(LENDER), 1);
        assertEq(loan.credits(BORROWER), 0, "zero surplus means no credit");
        assertEq(loan.totalCredits(), 1);
        assertTrue(loan.isCreditSolvent());
        vm.expectRevert(bytes("no credit"));
        vm.prank(BORROWER);
        loan.withdrawCredit(payable(BORROWER));

        vm.prank(LENDER);
        loan.withdrawCredit(payable(LENDER));
        assertEq(address(loan).balance, 0);
        assertEq(loan.totalCredits(), 0);
    }

    function testFuzz_LenderOnlyWaiverPreservesAlreadyPaidCredits(uint96 repaymentRaw) public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        uint256 paid = uint256(repaymentRaw) % 1.1 ether;
        if (paid > 0) {
            vm.prank(BORROWER);
            loan.repay{value: paid}(id);
        }
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);

        vm.expectRevert(bytes("not lender"));
        vm.prank(ARBITER);
        loan.lenderWaive(id);
        vm.expectRevert(bytes("not lender"));
        vm.prank(BORROWER);
        loan.lenderWaive(id);

        vm.prank(LENDER);
        loan.lenderWaive(id);
        assertEq(loan.credits(LENDER), paid, "already paid ETH cannot disappear");
        assertEq(address(loan).balance, paid, "no new/fake credit");
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);
        assertEq(collateral.ownerOf(1), BORROWER);
        assertEq(collateral.totalRedeemableValue(), 2 ether);
    }

    function testFuzz_DefaultCureRequiresExactETHAndPreventsLiquidation(uint96 repaidRaw) public {
        uint256 id = _propose(2 ether, 1 ether, 1.1 ether);
        _fund(id, 1 ether);
        uint256 paid = uint256(repaidRaw) % 1.1 ether;
        if (paid > 0) {
            vm.prank(BORROWER);
            loan.repay{value: paid}(id);
        }
        vm.warp(block.timestamp + 4 days);
        loan.declareDefault(id);

        uint256 owed = 1.1 ether - paid;
        vm.expectRevert(bytes("exact payoff required"));
        vm.prank(OUTSIDER);
        loan.settleAfterDefault{value: owed - 1}(id);
        assertEq(loan.credits(LENDER), paid);

        vm.prank(OUTSIDER);
        loan.settleAfterDefault{value: owed}(id);
        assertEq(loan.credits(LENDER), 1.1 ether, "full lender claim must be funded");
        assertEq(loan.totalCredits(), 1.1 ether);
        assertEq(address(loan).balance, 1.1 ether);
        vm.expectRevert(bytes("not saleable"));
        loan.startSale(id);
        vm.expectRevert(bytes("not awaiting resolution"));
        vm.prank(OUTSIDER);
        loan.settleAfterDefault{value: owed}(id);
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);
        assertEq(collateral.ownerOf(1), BORROWER);
    }

}
