// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/OECLPartitionedClaimWitness.sol";
import "../contracts/BilateralTimeboundReserve.sol";

/// @notice A bounded impossibility/counterexample experiment:
/// the six-function ABI's aggregate locks and allowances cannot identify
/// which spender owns a live reserved portion. Tests below deliberately
/// simulate a privileged-state substitution via vm.prank; they DO NOT claim
/// honest immutable loan/app contracts can be impersonated on a real EVM.
contract OECLControllerAllocationV5Test is Test {
    address internal borrower = address(0xB001);
    address internal lender = address(0x1E0D);
    address internal beneficiary = address(0xBEEF);
    address internal buyer = address(0xB0B);
    bytes32 internal constant A_TERMS = keccak256("oecl-v5-A");
    bytes32 internal constant B_TERMS = keccak256("oecl-v5-B");

    OECLCompositionGate internal gate;
    OECLPartitionedClaimWitness internal witness;
    ReservableConditionalETHReference internal nft;
    BilateralTimeboundReserve internal appA;
    PartitionedReserveLoanPoC internal appB;

    function setUp() public {
        OECLCanonicalAssetFactory assets = new OECLCanonicalAssetFactory();
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(address(assets));
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(address(assets));
        gate = new OECLCompositionGate(address(assets), address(accounting), address(recovery));
        witness = new OECLPartitionedClaimWitness(address(gate));
        nft = ReservableConditionalETHReference(gate.deployConditionalAsset());
        appA = BilateralTimeboundReserve(gate.deployBilateralAccounting(address(nft)));
        appB = PartitionedReserveLoanPoC(payable(witness.deployLoan(address(nft))));

        vm.deal(borrower, 20 ether);
        vm.deal(lender, 20 ether);
        vm.deal(beneficiary, 20 ether);
        vm.deal(buyer, 20 ether);
        vm.prank(borrower);
        nft.mint{value: 2 ether}();
    }

    function _lockA(uint256 amount) internal {
        vm.startPrank(borrower);
        nft.approveReserve(1, address(appA), address(0), amount);
        uint256 agreement = appA.propose(
            1, amount, beneficiary, uint64(block.timestamp + 5 days), A_TERMS
        );
        vm.stopPrank();
        vm.prank(beneficiary);
        appA.accept(agreement, A_TERMS);
    }

    function _openB(uint256 collateral, uint256 principal, uint256 payoff)
        internal returns (uint256 id)
    {
        PartitionedReserveLoanPoC.Offer memory offer = PartitionedReserveLoanPoC.Offer({
            tokenId: 1, lender: lender,
            principal: principal, payoff: payoff, collateral: collateral,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days, grace: 1 hours, termsHash: B_TERMS
        });
        vm.startPrank(borrower);
        nft.approve(address(appB), 1);
        id = appB.propose(offer);
        vm.stopPrank();
        vm.prank(lender);
        appB.fund{value: principal}(id, B_TERMS);
    }

    function _mature(uint256 id) internal {
        PartitionedReserveLoanPoC.Loan memory l = appB.loanInfo(id);
        vm.warp(uint256(l.dueAt) + l.grace + 1);
    }

    function _assessment(uint256 id)
        internal view returns (OECLPartitionedClaimWitness.Evidence memory)
    {
        return witness.assess(
            address(nft), address(appB), id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
    }

    function test_RealControllerLocksAndOtherPortionAreIndependentlyVisible() public {
        _lockA(0.6 ether);
        uint256 id = _openB(1.2 ether, 1 ether, 1.1 ether);
        _mature(id);
        OECLPartitionedClaimWitness.Evidence memory e = _assessment(id);
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        assertEq(e.controllerLocked, 1.2 ether);
        assertEq(e.otherLocked, 0.6 ether);
        assertEq(e.locked, 1.8 ether);
        assertEq(e.backing, 2 ether);
        assertEq(nft.lockedBy(1, address(appA), address(0)), 0.6 ether);
        assertEq(nft.lockedBy(1, address(appB), address(0)), 1.2 ether);

        appB.liquidate(id);
        assertEq(nft.lockedBy(1, address(appB), address(0)), 0);
        assertEq(nft.lockedBy(1, address(appA), address(0)), 0.6 ether);
        assertEq(nft.lockedValue(1, address(0)), 0.6 ether);
        assertEq(nft.backingOf(1), 0.8 ether);
        assertEq(appB.credits(lender), 1.1 ether);
    }

    function test_SameAggregateAndSixReadSurfacesDifferentController_NowRejected() public {
        _lockA(0.6 ether);
        uint256 id = _openB(1.2 ether, 1 ether, 1.1 ether);
        _mature(id);

        OECLPartitionedClaimWitness.Evidence memory original = _assessment(id);
        assertEq(uint256(original.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        assertEq(nft.reserveAllowance(1, address(appA), address(0)), 0);
        assertEq(nft.reserveAllowance(1, address(appB), address(0)), 0);

        // In an intentionally adversarial state, B's accounting reservation is
        // released without changing its funded-loan ledger. That caller cannot
        // be impersonated on mainnet; Foundry prank models a compromised app.
        vm.prank(address(appB));
        nft.releaseValue(1, address(0), 1.2 ether);

        // The 1.2 ETH is re-reserved by A, preserving the exact aggregate
        // 1.8 ETH lock. Both spender allowances can remain visibly zero.
        vm.prank(address(appB)); // app B is still current NFT custodian
        nft.approveReserve(1, address(appA), address(0), 1.8 ether);
        vm.prank(address(appA));
        nft.reserveValue(1, address(0), 1.2 ether);
        vm.prank(address(appB));
        nft.approveReserve(1, address(appB), address(0), 0);

        // All six core-interface VIEW observations are unchanged.
        assertEq(nft.backingOf(1), original.backing);
        assertEq(nft.lockedValue(1, address(0)), original.locked);
        assertEq(nft.availableValue(1, address(0)), original.available);
        assertEq(nft.reserveAllowance(1, address(appA), address(0)), 0);
        assertEq(nft.reserveAllowance(1, address(appB), address(0)), 0);
        assertEq(nft.ownerOf(1), address(appB));
        assertTrue(nft.isSolvent());

        // But the economically crucial control of the collateral has changed.
        assertEq(nft.lockedBy(1, address(appA), address(0)), 1.8 ether);
        assertEq(nft.lockedBy(1, address(appB), address(0)), 0);

        OECLPartitionedClaimWitness.Evidence memory changed = _assessment(id);
        assertEq(changed.locked, original.locked);
        assertEq(changed.available, original.available);
        assertEq(changed.controllerLocked, 0);
        assertEq(changed.otherLocked, 1.8 ether);
        assertEq(uint256(changed.verdict), uint256(OECLPartitionedClaimWitness.Verdict.REJECT));
        assertEq(uint256(changed.reason),
            uint256(OECLPartitionedClaimWitness.Reason.ControllerAllocationMismatch));
        assertTrue(changed.evidenceHash != original.evidenceHash);

        // The actual loan also fails closed, rather than withdrawing another
        // application's ETH. No settlement payout or NFT backing is lost.
        vm.expectRevert(bytes("controller lock mismatch"));
        appB.liquidate(id);
        assertEq(appB.credits(lender), 0);
        assertEq(address(nft).balance, 2 ether);
        assertEq(nft.lockedValue(1, address(0)), 1.8 ether);
    }

    function test_ExistingControllerLockPersistsThroughTransferAndExpiredApproval() public {
        _lockA(0.6 ether);
        assertEq(nft.lockedBy(1, address(appA), address(0)), 0.6 ether);
        vm.prank(borrower);
        nft.transferFrom(borrower, buyer, 1);
        assertEq(nft.reserveAllowance(1, address(appA), address(0)), 0);
        assertEq(nft.lockedBy(1, address(appA), address(0)), 0.6 ether);
        vm.prank(buyer);
        nft.approveReserve(1, address(appA), address(0), 0);
        assertEq(nft.lockedBy(1, address(appA), address(0)), 0.6 ether);
        assertEq(nft.availableValue(1, address(0)), 1.4 ether);
    }

    function testFuzz_AuthorizedIndependentSliceAmountsMatchDirectStorage(
        uint96 aSeed, uint96 bSeed
    ) public {
        uint256 a = 0.1 ether + uint256(aSeed) % (0.8 ether);
        uint256 b = 0.1 ether + uint256(bSeed) % (2 ether - a - 0.1 ether);
        _lockA(a);
        uint256 principal = b / 2;
        uint256 id = _openB(b, principal, b);
        _mature(id);

        OECLPartitionedClaimWitness.Evidence memory e = _assessment(id);
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        assertEq(e.controllerLocked, b);
        assertEq(e.otherLocked, a);
        assertEq(e.locked, a + b);
        assertEq(e.available, 2 ether - a - b);
        assertEq(nft.lockedBy(1, address(appA), address(0)), a);
        assertEq(nft.lockedBy(1, address(appB), address(0)), b);
        appB.liquidate(id);
        assertEq(nft.lockedBy(1, address(appA), address(0)), a);
        assertEq(nft.lockedBy(1, address(appB), address(0)), 0);
        assertEq(appB.credits(lender), b);
        assertEq(nft.backingOf(1), 2 ether - b);
    }
}
