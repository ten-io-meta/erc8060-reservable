// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/OECLCompositionGate.sol";
import "../contracts/test/AuctionAdversarialMocks.sol";

/// @notice OECL v2 exercises a bounded provenance/capability gate against
/// immutable local references and existing independent application contracts.
/// Test passing is NOT an audit and not an economic safety guarantee.
contract OECLCompositionGateV2Test is Test {
    OECLCompositionGate internal gate;
    address internal borrower = address(0xB001);
    address internal lender = address(0x1E0D);
    address internal arbiter = address(0xA8B);
    address internal stranger = address(0xBAD);

    function setUp() public {
        OECLCanonicalAssetFactory assets = new OECLCanonicalAssetFactory();
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(address(assets));
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(address(assets));
        gate = new OECLCompositionGate(address(assets), address(accounting), address(recovery));
        assertLe(address(gate).code.length, 24576, "gate runtime exceeds EIP-170");
        assertLe(address(assets).code.length, 24576, "asset factory runtime exceeds EIP-170");
        assertLe(address(accounting).code.length, 24576, "accounting factory runtime exceeds EIP-170");
        assertLe(address(recovery).code.length, 24576, "recovery factory runtime exceeds EIP-170");
        vm.deal(borrower, 20 ether);
        vm.deal(lender, 20 ether);
        vm.deal(stranger, 20 ether);
    }

    function _assert(
        address asset,
        address application,
        OECLCompositionGate.Capability cap,
        uint256 loanId,
        OECLCompositionGate.Verdict verdict,
        OECLCompositionGate.Reason reason
    ) internal view {
        (OECLCompositionGate.Verdict actual, OECLCompositionGate.Reason why) =
            gate.assess(asset, application, cap, loanId);
        assertEq(uint256(actual), uint256(verdict), "incorrect verdict");
        assertEq(uint256(why), uint256(reason), "incorrect reason");
    }

    function test_CanonicalStrictCreationSupportsBurnButNotAccountingReservations() public {
        address asset = gate.deployStrictAsset();
        vm.prank(borrower);
        ERC8060NativeETHReference(asset).mint{value: 2 ether}();
        assertEq(address(asset).balance, 2 ether);
        _assert(asset, address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        _assert(asset, address(0), OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.UnsupportedCapability);
        assertTrue(ERC8060NativeETHReference(asset).isSolvent());
    }

    function test_IdenticalExternalStrictCodeIsUnknownDespiteMatchingBytecode() public {
        address canonical = gate.deployStrictAsset();
        ERC8060NativeETHReference outside = new ERC8060NativeETHReference();
        assertEq(canonical.codehash, address(outside).codehash, "same runtime expected");
        _assert(address(outside), address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0,
            OECLCompositionGate.Verdict.UNKNOWN, OECLCompositionGate.Reason.UnrecognizedAsset);
        _assert(canonical, address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
    }

    function test_FakeValueAndFundedFakeNeverReceiveProvenance() public {
        AuctionFakeValueNFT fake = new AuctionFakeValueNFT();
        vm.prank(borrower);
        fake.mint();
        vm.deal(address(fake), 2 ether); // donated balance does not prove liabilities
        assertEq(fake.valueOf(1), 2 ether);
        _assert(address(fake), address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0,
            OECLCompositionGate.Verdict.UNKNOWN, OECLCompositionGate.Reason.UnrecognizedAsset);
    }

    function test_CanonicalConditionalAppSupportsAccountingButNotDefaultRecovery() public {
        address asset = gate.deployConditionalAsset();
        address a = gate.deployBilateralAccounting(asset);
        address b = gate.deployRepaymentOnly(asset);
        vm.prank(borrower);
        ReservableConditionalETHReference(asset).mint{value: 2 ether}();
        _assert(asset, a, OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        _assert(asset, b, OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        _assert(asset, address(0), OECLCompositionGate.Capability.OwnerWithdrawAvailable, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        _assert(asset, b, OECLCompositionGate.Capability.CreditorCreditUponActualRepayment, 0,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        _assert(asset, b, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 0,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.UnsupportedCapability);
        _assert(asset, address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.UnsupportedCapability);
    }

    function test_FailClosedForUnregisteredAppAndCrossAssetComposition() public {
        address a = gate.deployConditionalAsset();
        address b = gate.deployConditionalAsset();
        address accepted = gate.deployBilateralAccounting(a);
        BilateralTimeboundReserve outside = new BilateralTimeboundReserve(a);
        _assert(a, address(outside), OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.UNKNOWN, OECLCompositionGate.Reason.UnrecognizedApplication);
        _assert(b, accepted, OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.WrongAsset);
        _assert(address(0xBADC0DE), accepted, OECLCompositionGate.Capability.ReserveAccounting, 0,
            OECLCompositionGate.Verdict.UNKNOWN, OECLCompositionGate.Reason.UnrecognizedAsset);
        vm.expectRevert(bytes("strict NFT required"));
        gate.deployCustodialLiquidator(a);
        address strictAsset = gate.deployStrictAsset();
        vm.expectRevert(bytes("conditional NFT required"));
        gate.deployRepaymentOnly(strictAsset);
    }

    function _createLoan(address asset, address app)
        internal returns (CustodiedCollateralLoanPoC loan)
    {
        loan = CustodiedCollateralLoanPoC(payable(app));
        vm.startPrank(borrower);
        ERC8060NativeETHReference(asset).mint{value: 2 ether}();
        ERC8060NativeETHReference(asset).approve(app, 1);
        CustodiedCollateralLoanPoC.Offer memory offer = CustodiedCollateralLoanPoC.Offer({
            tokenId: 1,
            lender: lender,
            arbiter: arbiter,
            principal: 1 ether,
            payoff: 1.2 ether,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days,
            grace: 0,
            challenge: 60,
            arbitrateFor: 60,
            termsHash: keccak256("OECL-v2-canonical-loan"),
            saleStartPrice: 3 ether,
            saleDuration: 1 hours
        });
        loan.propose(offer);
        vm.stopPrank();
        _assert(asset, app, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.NoLiveFundedLoan);
        vm.prank(lender);
        loan.fund{value: 1 ether}(1, offer.termsHash);
    }

    function test_CanonicalCollateralIsAcceptableOnlyDuringFundedCustodyLifecycle() public {
        address asset = gate.deployStrictAsset();
        address app = gate.deployCustodialLiquidator(asset);
        _assert(asset, app, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.NoLiveFundedLoan);

        CustodiedCollateralLoanPoC loan = _createLoan(asset, app);
        _assert(asset, app, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);
        assertEq(ERC8060NativeETHReference(asset).ownerOf(1), app, "custody must be real");

        CustodiedCollateralLoanPoC.Loan memory state = loan.loanInfo(1);
        vm.warp(uint256(state.dueAt) + 1);
        loan.declareDefault(1);
        vm.warp(block.timestamp + 61);
        loan.startSale(1);
        _assert(asset, app, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.ACCEPT, OECLCompositionGate.Reason.Compatible);

        vm.warp(block.timestamp + 3601);
        loan.burnUnsold(1);
        assertEq(loan.credits(lender), 1.2 ether, "real creditor claim");
        assertEq(loan.credits(borrower), 0.8 ether, "real borrower surplus");
        assertEq(address(app).balance, 2 ether, "credits funded by real ETH");
        assertTrue(loan.isCreditSolvent());
        _assert(asset, app, OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.REJECT, OECLCompositionGate.Reason.NoLiveFundedLoan);

        uint256 before = lender.balance;
        vm.prank(lender);
        loan.withdrawCredit(payable(lender));
        assertEq(lender.balance, before + 1.2 ether, "creditor can collect actual ETH");
    }

    function test_ReceiptReportsInstantaneousResultButDoesNotCertifyFutureSafety() public {
        address asset = gate.deployStrictAsset();
        vm.recordLogs();
        (OECLCompositionGate.Verdict verdict, OECLCompositionGate.Reason why) =
            gate.recordAssessment(asset, address(0), OECLCompositionGate.Capability.StrictOwnerBurn, 0);
        assertEq(uint256(verdict), uint256(OECLCompositionGate.Verdict.ACCEPT));
        assertEq(uint256(why), uint256(OECLCompositionGate.Reason.Compatible));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(gate)) continue;
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256(
                "AssessmentReceipt(address,address,uint8,uint256,uint8,uint8)"
            )) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), asset);
                break;
            }
        }
        assertTrue(found, "expected real event receipt");
    }

    function testFuzz_UnknownAssetIsNeverAccepted(uint160 arbitrary) public {
        address asset = address(arbitrary);
        vm.assume(asset != address(0));
        vm.assume(gate.assetProfiles(asset) == OECLCompositionGate.AssetProfile.Unrecognized);
        _assert(asset, address(0), OECLCompositionGate.Capability.CreditorDefaultRecoveryPath, 1,
            OECLCompositionGate.Verdict.UNKNOWN, OECLCompositionGate.Reason.UnrecognizedAsset);
    }
}
