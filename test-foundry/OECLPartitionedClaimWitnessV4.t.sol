// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/OECLPartitionedClaimWitness.sol";
import "../contracts/BilateralTimeboundReserve.sol";
import "../contracts/test/AuctionAdversarialMocks.sol";

contract OECLPartitionedClaimWitnessV4Test is Test {
    address internal borrower = address(0xB001);
    address internal creditor = address(0x1E0D);
    address internal beneficiary = address(0xBEEF);
    address internal outsider = address(0xBAD);
    bytes32 internal constant A_TERMS = keccak256("v4-independent-escrow");
    bytes32 internal constant B_TERMS = keccak256("v4-verified-executable-slice");

    OECLCompositionGate internal gate;
    OECLPartitionedClaimWitness internal witness;
    ReservableConditionalETHReference internal nft;
    BilateralTimeboundReserve internal appA;
    PartitionedReserveLoanPoC internal loan;

    function setUp() public {
        OECLCanonicalAssetFactory assets = new OECLCanonicalAssetFactory();
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(address(assets));
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(address(assets));
        gate = new OECLCompositionGate(address(assets), address(accounting), address(recovery));

        witness = new OECLPartitionedClaimWitness(address(gate));
        nft = ReservableConditionalETHReference(gate.deployConditionalAsset());
        appA = BilateralTimeboundReserve(gate.deployBilateralAccounting(address(nft)));
        loan = PartitionedReserveLoanPoC(payable(witness.deployLoan(address(nft))));

        assertEq(witness.loanFactory().boundAsset(address(loan)), address(nft));
        assertLe(address(witness).code.length, 24576, "witness violates EIP-170");
        assertLe(address(witness.loanFactory()).code.length, 24576, "factory violates EIP-170");

        vm.deal(borrower, 20 ether);
        vm.deal(creditor, 20 ether);
        vm.deal(beneficiary, 20 ether);
        vm.deal(outsider, 20 ether);
        vm.prank(borrower);
        nft.mint{value: 2 ether}();
    }

    function _check(address asset, address app, uint256 id,
        OECLPartitionedClaimWitness.Kind kind,
        OECLPartitionedClaimWitness.Verdict verdict,
        OECLPartitionedClaimWitness.Reason reason) internal view
    {
        OECLPartitionedClaimWitness.Evidence memory e =
            witness.assess(asset, app, id, kind);
        assertEq(uint256(e.verdict), uint256(verdict), "wrong verdict");
        assertEq(uint256(e.reason), uint256(reason), "wrong reason");
        assertTrue(e.evidenceHash != bytes32(0), "evidence must be scoped");
    }

    function _lockA(uint256 amount) internal returns (uint256 agreement) {
        vm.startPrank(borrower);
        nft.approveReserve(1, address(appA), address(0), amount);
        agreement = appA.propose(1, amount, beneficiary,
            uint64(block.timestamp + 5 days), A_TERMS);
        vm.stopPrank();
        vm.prank(beneficiary);
        appA.accept(agreement, A_TERMS);
    }

    function _proposeB(uint256 amount, uint256 principal, uint256 payoff)
        internal returns (uint256 id)
    {
        PartitionedReserveLoanPoC.Offer memory offer = PartitionedReserveLoanPoC.Offer({
            tokenId: 1, lender: creditor, principal: principal, payoff: payoff,
            collateral: amount, fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days, grace: 1 hours, termsHash: B_TERMS
        });
        vm.startPrank(borrower);
        nft.approve(address(loan), 1);
        id = loan.propose(offer);
        vm.stopPrank();
    }

    function _fundB(uint256 id, uint256 principal) internal {
        vm.prank(creditor);
        loan.fund{value: principal}(id, B_TERMS);
    }

    function _open() internal returns (uint256 id) {
        _lockA(0.6 ether);
        id = _proposeB(1.2 ether, 1 ether, 1.1 ether);
        _fundB(id, 1 ether);
    }

    function _mature(uint256 id) internal {
        PartitionedReserveLoanPoC.Loan memory l = loan.loanInfo(id);
        vm.warp(uint256(l.dueAt) + l.grace + 1);
    }

    function test_AccountingOnlyIsNotAClaimOrFullBurn() public view {
        _check(address(nft), address(appA), 0,
            OECLPartitionedClaimWitness.Kind.AccountingSurface,
            OECLPartitionedClaimWitness.Verdict.ACCEPT,
            OECLPartitionedClaimWitness.Reason.Compatible);
        _check(address(nft), address(appA), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.UNKNOWN,
            OECLPartitionedClaimWitness.Reason.UnrecognizedApp);
        _check(address(nft), address(loan), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotFunded);
        _check(address(nft), address(0), 0,
            OECLPartitionedClaimWitness.Kind.StrictBurnProfile,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.WrongProfile);
    }

    function test_ExplicitStrictBurnNeverMisclassifiedAsPartialClaim() public {
        address strict = gate.deployStrictAsset();
        vm.prank(borrower);
        ERC8060NativeETHReference(strict).mint{value: 1 ether}();

        _check(strict, address(0), 0,
            OECLPartitionedClaimWitness.Kind.StrictBurnProfile,
            OECLPartitionedClaimWitness.Verdict.ACCEPT,
            OECLPartitionedClaimWitness.Reason.Compatible);
        _check(strict, address(loan), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.WrongProfile);
        _check(strict, address(0), 0,
            OECLPartitionedClaimWitness.Kind.AccountingSurface,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.WrongProfile);
    }

    function test_FundingAndMaturityAreNecessaryBeforeAcceptingExecution() public {
        _lockA(0.6 ether);
        uint256 id = _proposeB(1.2 ether, 1 ether, 1.1 ether);

        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotFunded);

        _fundB(id, 1 ether);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotYetExecutable);

        PartitionedReserveLoanPoC.Loan memory l = loan.loanInfo(id);
        vm.warp(uint256(l.dueAt) + l.grace);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotYetExecutable);

        vm.warp(block.timestamp + 1);
        OECLPartitionedClaimWitness.Evidence memory e = witness.assess(
            address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        assertEq(uint256(e.reason), uint256(OECLPartitionedClaimWitness.Reason.Compatible));
        assertEq(e.tokenId, 1);
        assertEq(e.creditor, creditor);
        assertEq(e.collateral, 1.2 ether);
        assertEq(e.payoff, 1.1 ether);
        assertEq(e.backing, 2 ether);
        assertEq(e.locked, 1.8 ether);
        assertEq(e.available, 0.2 ether);
        assertEq(e.dueAfterGrace, uint256(l.dueAt) + l.grace);
        assertEq(e.observedBlock, block.number);
    }

    function test_EndToEndExecutionReversesVerdictAndPreservesOtherApp() public {
        uint256 id = _open();
        _mature(id);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.ACCEPT,
            OECLPartitionedClaimWitness.Reason.Compatible);

        loan.liquidate(id);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotFunded);

        assertEq(nft.backingOf(1), 0.8 ether);
        assertEq(nft.lockedValue(1, address(0)), 0.6 ether);
        assertEq(nft.availableValue(1, address(0)), 0.2 ether);
        assertEq(loan.credits(creditor), 1.1 ether);
        assertEq(loan.credits(borrower), 0.1 ether);
        assertEq(address(loan).balance, 1.2 ether);
        assertTrue(nft.isSolvent());
        vm.prank(borrower);
        loan.claimCollateral(id, borrower);
        assertEq(nft.ownerOf(1), borrower);
    }

    function test_RepaymentInvalidatesEvidenceAtSameLoanId() public {
        uint256 id = _open();
        _mature(id);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.ACCEPT,
            OECLPartitionedClaimWitness.Reason.Compatible);
        vm.prank(borrower);
        loan.repay{value: 1.1 ether}(id);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotFunded);
        assertEq(nft.lockedValue(1, address(0)), 0.6 ether);
        assertEq(loan.credits(creditor), 1.1 ether);
        vm.expectRevert(bytes("not active"));
        loan.liquidate(id);
    }

    function test_ExternalSameRuntimeLoanAndNFTCannotSelfAttest() public {
        address outsideLoan = address(new PartitionedReserveLoanPoC(address(nft), address(gate)));
        assertEq(address(loan).codehash, outsideLoan.codehash,
            "same immutable constructor arguments imply same runtime");
        _check(address(nft), outsideLoan, 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.UNKNOWN,
            OECLPartitionedClaimWitness.Reason.UnrecognizedApp);

        ReservableConditionalETHReference outsideNFT = new ReservableConditionalETHReference();
        assertEq(address(nft).codehash, address(outsideNFT).codehash);
        _check(address(outsideNFT), address(loan), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.UNKNOWN,
            OECLPartitionedClaimWitness.Reason.UnrecognizedAsset);

        AuctionFakeValueNFT fake = new AuctionFakeValueNFT();
        vm.deal(address(fake), 2 ether);
        _check(address(fake), address(loan), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.UNKNOWN,
            OECLPartitionedClaimWitness.Reason.UnrecognizedAsset);
    }

    function test_KnownLoanWithDifferentRegisteredAssetIsRejected() public {
        address asset2 = gate.deployConditionalAsset();
        _check(asset2, address(loan), 1,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.WrongAsset);
    }

    function test_EvidenceReceiptIsBoundToCurrentStateNotFutureAuthority() public {
        uint256 id = _open();
        _mature(id);
        OECLPartitionedClaimWitness.Evidence memory expected = witness.assess(
            address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
        vm.recordLogs();
        OECLPartitionedClaimWitness.Evidence memory receipt = witness.record(
            address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
        assertEq(expected.evidenceHash, receipt.evidenceHash);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool emitted;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(witness) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] ==
                keccak256("EvidenceReceipt(address,address,uint256,uint8,uint8,uint8,bytes32)")) {
                emitted = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(nft));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(loan));
                assertEq(uint256(logs[i].topics[3]), id);
            }
        }
        assertTrue(emitted, "missing event receipt");
        loan.liquidate(id);
        bytes32 afterHash = witness.assess(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow).evidenceHash;
        assertTrue(receipt.evidenceHash != afterHash, "stale evidence should change");
    }

    function testFuzz_DisjointLocksNeedFundingAndMaturityForExecutableEvidence(
        uint96 aSeed, uint96 bSeed
    ) public {
        uint256 a = 0.1 ether + (uint256(aSeed) % 0.8 ether);
        uint256 b = 0.1 ether + (uint256(bSeed) % (2 ether - a - 0.1 ether));
        _lockA(a);
        uint256 principal = b / 2;
        uint256 id = _proposeB(b, principal, b);
        _fundB(id, principal);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotYetExecutable);

        _mature(id);
        OECLPartitionedClaimWitness.Evidence memory e = witness.assess(
            address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        assertEq(e.backing, 2 ether);
        assertEq(e.locked, a + b);
        assertEq(e.available, 2 ether - a - b);
        loan.liquidate(id);
        assertEq(nft.lockedValue(1, address(0)), a, "unrelated lock unchanged");
        assertEq(nft.backingOf(1), 2 ether - b);
        assertEq(loan.credits(creditor), b);
        _check(address(nft), address(loan), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow,
            OECLPartitionedClaimWitness.Verdict.REJECT,
            OECLPartitionedClaimWitness.Reason.NotFunded);
    }
}
