// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PartitionedReserveLoanPoC.sol";
import "../contracts/OECLCompositionGate.sol";
import "../contracts/BilateralTimeboundReserve.sol";
import "../contracts/test/AuctionAdversarialMocks.sol";

/// @notice Falsifiable proof-of-concept: accounting locks for unrelated A
///         survive a real B creditor liquidation. This is NOT strict ERC-8060
///         and does not prove security for arbitrary third-party NFT contracts.
contract OECLPartitionedReserveV3Test is Test {
    address internal borrower = address(0xB001);
    address internal lender = address(0x1E0D);
    address internal beneficiary = address(0xBEEF);
    address internal buyer = address(0xB0B);
    address internal outsider = address(0xBAD);
    address internal constant ETH_ASSET = address(0);
    bytes32 internal constant TERMS_A = keccak256("OECL-v3-independent-A");
    bytes32 internal constant TERMS_B = keccak256("OECL-v3-partitioned-loan");

    OECLCompositionGate internal gate;
    ReservableConditionalETHReference internal nft;
    BilateralTimeboundReserve internal appA;
    PartitionedReserveLoanPoC internal loan;

    uint64 internal expiryA;
    uint256 internal agreementA;

    function setUp() public {
        OECLCanonicalAssetFactory assets = new OECLCanonicalAssetFactory();
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(address(assets));
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(address(assets));
        gate = new OECLCompositionGate(address(assets), address(accounting), address(recovery));
        nft = ReservableConditionalETHReference(gate.deployConditionalAsset());
        appA = BilateralTimeboundReserve(gate.deployBilateralAccounting(address(nft)));
        loan = new PartitionedReserveLoanPoC(address(nft), address(gate));
        assertLe(address(loan).code.length, 24576, "loan runtime exceeds EIP-170");

        vm.deal(borrower, 20 ether);
        vm.deal(lender, 20 ether);
        vm.deal(beneficiary, 20 ether);
        vm.deal(buyer, 20 ether);
        vm.deal(outsider, 20 ether);

        vm.prank(borrower);
        assertEq(nft.mint{value: 2 ether}(), 1);
        assertEq(nft.backingOf(1), 2 ether);
    }

    function _lockA(uint256 amount) internal {
        expiryA = uint64(block.timestamp + 5 days);
        vm.startPrank(borrower);
        nft.approveReserve(1, address(appA), ETH_ASSET, amount);
        agreementA = appA.propose(1, amount, beneficiary, expiryA, TERMS_A);
        vm.stopPrank();
        vm.prank(beneficiary);
        appA.accept(agreementA, TERMS_A);
    }

    function _proposeB(uint256 collateral, uint256 principal, uint256 payoff)
        internal returns (uint256 id)
    {
        PartitionedReserveLoanPoC.Offer memory offer = PartitionedReserveLoanPoC.Offer({
            tokenId: 1,
            lender: lender,
            principal: principal,
            payoff: payoff,
            collateral: collateral,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days,
            grace: 1 hours,
            termsHash: TERMS_B
        });
        vm.startPrank(borrower);
        nft.approve(address(loan), 1);
        id = loan.propose(offer);
        vm.stopPrank();
    }

    function _fundB(uint256 id, uint256 principal) internal {
        vm.prank(lender);
        loan.fund{value: principal}(id, TERMS_B);
    }

    function _openBoth() internal returns (uint256 id) {
        _lockA(0.6 ether);
        id = _proposeB(1.2 ether, 1 ether, 1.1 ether);
        _fundB(id, 1 ether);
        _assertAccounting(2 ether, 1.8 ether, 0.2 ether);
    }

    function _expireLoan(uint256 id) internal {
        PartitionedReserveLoanPoC.Loan memory l = loan.loanInfo(id);
        vm.warp(uint256(l.dueAt) + l.grace + 1);
    }

    function _assertAccounting(uint256 backing, uint256 locked, uint256 available)
        internal view
    {
        assertEq(nft.backingOf(1), backing, "backing must remain exact");
        assertEq(nft.lockedValue(1, ETH_ASSET), locked, "other locks must survive");
        assertEq(nft.availableValue(1, ETH_ASSET), available, "available mismatch");
        assertEq(backing, locked + available, "double allocation");
        assertEq(nft.totalBacked(), address(nft).balance, "vault ETH liabilities");
        assertTrue(nft.isSolvent(), "vault insolvent");
        assertTrue(loan.isCreditSolvent(), "credit insolvent");
    }

    function test_FundedDefaultEnforcesOnlyBAndPreservesAThenFullExit() public {
        uint256 id = _openBoth();
        assertEq(nft.ownerOf(1), address(loan), "loan must actually hold NFT");
        _expireLoan(id);

        uint256 beforeVault = address(nft).balance;
        loan.liquidate(id);
        _assertAccounting(0.8 ether, 0.6 ether, 0.2 ether);
        assertEq(beforeVault - address(nft).balance, 1.2 ether);
        assertEq(loan.credits(lender), 1.1 ether, "real creditor payout");
        assertEq(loan.credits(borrower), 0.1 ether, "borrower surplus");
        assertEq(loan.totalCredits(), 1.2 ether);
        assertEq(address(loan).balance, 1.2 ether);

        vm.expectRevert(bytes("not active"));
        loan.liquidate(id);
        vm.prank(borrower);
        loan.claimCollateral(id, borrower);
        assertEq(nft.ownerOf(1), borrower);
        _assertAccounting(0.8 ether, 0.6 ether, 0.2 ether);
        assertEq(loan.activeTokenLoan(1), 0);

        // Application A's entitlement is unchanged, including its expiry.
        (,uint256 amount,, , , , BilateralTimeboundReserve.Phase phase) =
            appA.agreements(agreementA);
        assertEq(amount, 0.6 ether);
        assertEq(uint256(phase), uint256(BilateralTimeboundReserve.Phase.Active));

        vm.prank(lender);
        loan.withdrawCredit(payable(lender));
        assertEq(loan.credits(lender), 0);
        vm.warp(uint256(expiryA) + 1);
        appA.releaseExpired(agreementA);
        _assertAccounting(0.8 ether, 0, 0.8 ether);
        uint256 before = borrower.balance;
        vm.prank(borrower);
        nft.redeemWhenUnlocked(1);
        assertEq(borrower.balance, before + 0.8 ether);
        assertEq(address(nft).balance, 0);
        assertEq(nft.totalBacked(), 0);
    }

    function test_RealRepaymentReleasesOnlyBAndDoesNotCancelA() public {
        uint256 id = _openBoth();
        vm.prank(outsider);
        loan.repay{value: 1.1 ether}(id); // unrelated payer may cure in real ETH
        _assertAccounting(2 ether, 0.6 ether, 1.4 ether);
        assertEq(loan.credits(lender), 1.1 ether);
        vm.expectRevert(bytes("not active"));
        loan.liquidate(id);
        vm.prank(borrower);
        loan.claimCollateral(id, borrower);
        assertEq(nft.ownerOf(1), borrower);
        _assertAccounting(2 ether, 0.6 ether, 1.4 ether);
        vm.prank(beneficiary);
        appA.releaseEarly(agreementA);
        _assertAccounting(2 ether, 0, 2 ether);
    }

    function test_OverReservationRevertsBeforeCustodyAndPreservesA() public {
        _lockA(0.9 ether);
        vm.startPrank(borrower);
        nft.approve(address(loan), 1);
        PartitionedReserveLoanPoC.Offer memory offer = PartitionedReserveLoanPoC.Offer({
            tokenId: 1, lender: lender, principal: 1 ether, payoff: 1.1 ether,
            collateral: 1.2 ether, fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days, grace: 0, termsHash: TERMS_B
        });
        vm.expectRevert(bytes("insufficient unreserved ETH"));
        loan.propose(offer);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), borrower);
        _assertAccounting(2 ether, 0.9 ether, 1.1 ether);
        assertEq(loan.nextLoanId(), 1, "reverted proposal allocated loan");
    }

    function test_NeitherBorrowerNorStrangersCanBreakBReserveWhileCustodied() public {
        uint256 id = _openBoth();
        vm.startPrank(borrower);
        vm.expectRevert(bytes("not NFT owner"));
        nft.withdrawAvailable(1, 0.2 ether);
        vm.expectRevert(bytes("not NFT owner"));
        nft.approveReserve(1, outsider, ETH_ASSET, 1 ether);
        vm.expectRevert(bytes("release exceeds allocation"));
        nft.releaseValue(1, ETH_ASSET, 1.2 ether);
        vm.expectRevert(bytes("NFT still encumbered by loan"));
        loan.claimCollateral(id, borrower);
        vm.stopPrank();
        vm.prank(outsider);
        vm.expectRevert(bytes("still repayable"));
        loan.liquidate(id);
        vm.prank(borrower);
        vm.expectRevert(bytes("token already in loan"));
        loan.propose(PartitionedReserveLoanPoC.Offer({
            tokenId: 1, lender: lender, principal: 1 ether, payoff: 1.1 ether,
            collateral: 1.2 ether, fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days, grace: 0, termsHash: TERMS_B
        }));
        _assertAccounting(2 ether, 1.8 ether, 0.2 ether);
    }

    function test_AExpiresBeforeBDefaultAndOnlyItsLockIsReleased() public {
        uint256 id = _openBoth();
        vm.warp(uint256(expiryA) + 1);
        appA.releaseExpired(agreementA);
        _assertAccounting(2 ether, 1.2 ether, 0.8 ether);
        loan.liquidate(id);
        _assertAccounting(0.8 ether, 0, 0.8 ether);
        assertEq(loan.credits(lender), 1.1 ether);
    }

    function test_OrderingRepaymentFirstMakesLiquidationImpossible() public {
        uint256 id = _openBoth();
        _expireLoan(id);
        vm.prank(borrower);
        loan.repay{value: 1.1 ether}(id);
        vm.expectRevert(bytes("not active"));
        loan.liquidate(id);
        _assertAccounting(2 ether, 0.6 ether, 1.4 ether);
    }

    function test_OrderingLiquidationFirstMakesRepaymentImpossible() public {
        uint256 id = _openBoth();
        _expireLoan(id);
        loan.liquidate(id);
        vm.prank(borrower);
        vm.expectRevert(bytes("not active"));
        loan.repay{value: 1.1 ether}(id);
        _assertAccounting(0.8 ether, 0.6 ether, 0.2 ether);
    }

    function test_CancelUnfundedKeepsOtherLockAndRefundSafety() public {
        _lockA(0.6 ether);
        uint256 id = _proposeB(1.2 ether, 1 ether, 1.1 ether);
        _assertAccounting(2 ether, 1.8 ether, 0.2 ether);
        vm.prank(borrower);
        loan.cancelUnfunded(id);
        _assertAccounting(2 ether, 0.6 ether, 1.4 ether);
        vm.prank(lender);
        vm.expectRevert(bytes("not proposed"));
        loan.fund{value: 1 ether}(id, TERMS_B);
        vm.prank(borrower);
        loan.claimCollateral(id, borrower);
        assertEq(nft.ownerOf(1), borrower);
    }

    function test_OutsideIdenticalNFTAndFakeValueNFTRejectedByProvenance() public {
        ReservableConditionalETHReference externalCopy = new ReservableConditionalETHReference();
        assertEq(address(nft).codehash, address(externalCopy).codehash);
        vm.expectRevert(bytes("not factory-recognized NFT"));
        new PartitionedReserveLoanPoC(address(externalCopy), address(gate));

        AuctionFakeValueNFT fake = new AuctionFakeValueNFT();
        vm.expectRevert(bytes("untrusted conditional NFT"));
        new PartitionedReserveLoanPoC(address(fake), address(gate));
    }

    function testFuzz_PartitionedLiquidationPreservesArbitraryOtherLocks(
        uint96 aSeed, uint96 bSeed
    ) public {
        uint256 a = 0.1 ether + (uint256(aSeed) % 0.8 ether);
        uint256 b = 0.1 ether + (uint256(bSeed) % (2 ether - a - 0.1 ether));
        _lockA(a);
        uint256 principal = b < 1 ether ? b : 1 ether;
        uint256 id = _proposeB(b, principal, b);
        _fundB(id, principal);
        _assertAccounting(2 ether, a + b, 2 ether - a - b);
        _expireLoan(id);
        loan.liquidate(id);
        _assertAccounting(2 ether - b, a, 2 ether - a - b);
        assertEq(loan.credits(lender), b);
        assertEq(loan.totalCredits(), b);
        assertEq(address(loan).balance, b);
        assertEq(nft.lockedValue(1, ETH_ASSET), a);
    }
}
