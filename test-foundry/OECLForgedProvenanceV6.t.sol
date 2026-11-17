// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/OECLProvenancePin.sol";
import "../contracts/OECLPartitionedClaimWitness.sol";
import "../contracts/test/OECLForgedProvenanceMocks.sol";

/// @notice Adversarial provenance laboratory. These are real EVM constructor
/// bytecode-clones (not vm.etch or vm.store) with fraudulent initial storage.
/// The honest canonical factory and fixed-identity pin MUST fail closed.
/// The intentionally attacker-chosen factory/gate demonstrates the trust hole.
contract OECLForgedProvenanceV6Test is Test {
    OECLCompositionGate internal genuineGate;
    OECLPartitionedClaimWitness internal genuineWitness;
    OECLProvenancePin internal genuinePin;

    address internal borrower = address(0xB001);
    address internal lender = address(0x1E0D);
    address internal otherController = address(0xBAD);

    function setUp() public {
        OECLCanonicalAssetFactory assets = new OECLCanonicalAssetFactory();
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(address(assets));
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(address(assets));
        genuineGate = new OECLCompositionGate(
            address(assets), address(accounting), address(recovery)
        );
        genuineWitness = new OECLPartitionedClaimWitness(address(genuineGate));
        genuinePin = new OECLProvenancePin(address(genuineGate));
        assertLe(address(genuinePin).code.length, 24576, "pin oversized");
        vm.deal(borrower, 20 ether);
        vm.deal(lender, 20 ether);
    }

    function _map(uint256 key, uint256 position) private pure returns (bytes32) {
        return keccak256(abi.encode(key, position));
    }

    /// @dev Specific to the audited-in-lab OpenZeppelin v4 inheritance layout:
    /// ERC721 owner mapping at slot 2, balances at 3, guard status at 6,
    /// conditional NFT nextTokenId at 7, totalBacked at 8,
    /// backing mapping at 9, aggregate locked at 10, reservation map at 12.
    /// This is a REAL-EVM clone but is NOT created through the genuine mint.
    function _forgeConditionalWithFalseBalance() private returns (address forged) {
        bytes32[] memory keys = new bytes32[](6);
        bytes32[] memory values = new bytes32[](6);

        keys[0] = _map(1, 2); // _owners[1] = borrower (no mint)
        values[0] = bytes32(uint256(uint160(borrower)));
        keys[1] = _map(uint256(uint160(borrower)), 3); // _balances[borrower] = 1
        values[1] = bytes32(uint256(1));
        keys[2] = bytes32(uint256(7)); // nextTokenId = 2
        values[2] = bytes32(uint256(2));
        keys[3] = _map(1, 9); // _backing[1] = 2 ETH (no real deposit)
        values[3] = bytes32(uint256(2 ether));
        keys[4] = _map(1, 10); // aggregate _locked[1] = 1.2 ETH
        values[4] = bytes32(uint256(1.2 ether));

        // _reservations[1][otherController].locked = 1.2 ETH.
        bytes32 nested = _map(1, 12);
        bytes32 reservation = keccak256(abi.encode(otherController, nested));
        keys[5] = bytes32(uint256(reservation) + 1);
        values[5] = bytes32(uint256(1.2 ether));

        forged = address(new OECLRuntimeStorageForgingHarness(
            type(ReservableConditionalETHReference).runtimeCode, keys, values
        ));
        assertEq(forged.codehash,
            keccak256(type(ReservableConditionalETHReference).runtimeCode),
            "must be exact deployed runtime clone");
    }

    function _forgeAssetFactory(address counterfeitNFT) private returns (address forgedFactory) {
        bytes32[] memory keys = new bytes32[](1);
        bytes32[] memory values = new bytes32[](1);
        // A canonical factory has mapping(address => uint8) assetProfiles at slot 0.
        keys[0] = _map(uint256(uint160(counterfeitNFT)), 0);
        values[0] = bytes32(uint256(2)); // forge ConditionalReservableETH registration
        forgedFactory = address(new OECLRuntimeStorageForgingHarness(
            type(OECLCanonicalAssetFactory).runtimeCode, keys, values
        ));
        assertEq(forgedFactory.codehash,
            address(genuineGate.assets()).codehash,
            "factory runtime bytes MUST match");
        assertEq(OECLCanonicalAssetFactory(forgedFactory).assetProfiles(counterfeitNFT), 2);
    }

    function _deployForgedGate(address counterfeitNFT)
        private returns (OECLCompositionGate forgedGate)
    {
        address forgedFactory = _forgeAssetFactory(counterfeitNFT);
        OECLAccountingAppFactory accounting = new OECLAccountingAppFactory(forgedFactory);
        OECLRecoveryAppFactory recovery = new OECLRecoveryAppFactory(forgedFactory);
        // The actual gate constructor checks matching factory codehashes,
        // and both related factories point to forgedFactory. All checks pass.
        forgedGate = new OECLCompositionGate(
            forgedFactory, address(accounting), address(recovery)
        );
        assertEq(uint256(forgedGate.assetProfiles(counterfeitNFT)), 2);
        assertTrue(address(forgedGate.assets()) != address(genuineGate.assets()));
    }

    function test_BluntLiarSpoofsEveryGetterButGenuineGateReturnsUNKNOWN() public {
        OECLDishonestReservationNFT liar =
            new OECLDishonestReservationNFT(otherController, borrower);
        assertEq(address(liar).balance, 0);
        assertTrue(liar.isSolvent());
        assertEq(liar.backingOf(1), 2 ether);
        assertEq(liar.lockedValue(1, address(0)), 1.8 ether);
        assertEq(liar.lockedBy(1, otherController, address(0)), 1.2 ether);
        assertEq(liar.availableValue(1, address(0)), 0.2 ether);
        assertTrue(liar.supportsInterface(0xffffffff)); // fake ERC165 answer
        // Naive check: reported backing, accounting, controller and solvency ALL pass.
        assertTrue(
            liar.isSolvent() &&
            liar.backingOf(1) ==
                liar.lockedValue(1, address(0)) + liar.availableValue(1, address(0)) &&
            liar.lockedBy(1, otherController, address(0)) >= 1.2 ether
        );
        assertEq(uint256(genuineGate.assetProfiles(address(liar))), 0);
        (OECLCompositionGate.Verdict gv,) = genuineGate.assess(
            address(liar), address(0),
            OECLCompositionGate.Capability.ReserveAccounting, 0
        );
        assertEq(uint256(gv), uint256(OECLCompositionGate.Verdict.UNKNOWN));
        OECLPartitionedClaimWitness.Evidence memory e = genuineWitness.assess(
            address(liar), address(0), 0,
            OECLPartitionedClaimWitness.Kind.AccountingSurface
        );
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.UNKNOWN));
        // Even real ETH donated to a fake contract cannot authenticate a claim.
        vm.deal(address(liar), 0.25 ether);
        assertEq(liar.backingOf(1), 2 ether);
        assertTrue(liar.isSolvent());
        assertEq(uint256(genuinePin.inspectConditional(
            address(genuineGate), address(liar)
        )), uint256(OECLProvenancePin.Verdict.UNKNOWN));
    }

    function test_ExactRuntimeCloneCanForgeBackingLocksAndSolvencyWithoutETH() public {
        address counterfeit = _forgeConditionalWithFalseBalance();
        ReservableConditionalETHReference f = ReservableConditionalETHReference(counterfeit);

        assertEq(address(f).balance, 0);
        assertEq(f.nextTokenId(), 2);
        assertEq(f.ownerOf(1), borrower);
        assertEq(f.balanceOf(borrower), 1);
        assertEq(f.backingOf(1), 2 ether);
        assertEq(f.lockedValue(1, address(0)), 1.2 ether);
        assertEq(f.availableValue(1, address(0)), 0.8 ether);
        assertEq(f.lockedBy(1, otherController, address(0)), 1.2 ether);
        assertEq(f.totalBacked(), 0); // forged accounting says zero liability
        assertTrue(f.isSolvent()); // 0 ETH >= 0 falsely reports solvency

        // The EXACT authentic runtime cannot make unpaid promised ETH appear.
        vm.prank(borrower);
        vm.expectRevert(); // underflow in totalBacked, no real ETH transfer
        f.withdrawAvailable(1, 0.1 ether);

        assertEq(uint256(genuineGate.assetProfiles(counterfeit)), 0);
        assertEq(uint256(genuinePin.inspectConditional(address(genuineGate), counterfeit)),
            uint256(OECLProvenancePin.Verdict.UNKNOWN));
    }

    function test_ForgedFactoryPassesAllGateCodeHashesAndProducesFalseACCEPT() public {
        address counterfeit = _forgeConditionalWithFalseBalance();
        OECLCompositionGate forgedGate = _deployForgedGate(counterfeit);

        // Noncanonical factory forged the registry in its constructor while
        // returning the same deployed runtime as the canonical factory.
        assertEq(address(forgedGate.assets()).codehash, address(genuineGate.assets()).codehash);

        (OECLCompositionGate.Verdict fv,) = forgedGate.assess(
            counterfeit, address(0), OECLCompositionGate.Capability.ReserveAccounting, 0
        );
        assertEq(uint256(fv), uint256(OECLCompositionGate.Verdict.ACCEPT));
        OECLPartitionedClaimWitness unpinned = new OECLPartitionedClaimWitness(address(forgedGate));
        OECLPartitionedClaimWitness.Evidence memory e = unpinned.assess(
            counterfeit, address(0), 0, OECLPartitionedClaimWitness.Kind.AccountingSurface
        );
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT));
        // An independently PINNED trustworthy root rejects the exact same pair.
        assertEq(uint256(genuinePin.inspectConditional(address(forgedGate), counterfeit)),
            uint256(OECLProvenancePin.Verdict.UNKNOWN));
        assertEq(uint256(genuinePin.inspectConditional(address(genuineGate), counterfeit)),
            uint256(OECLProvenancePin.Verdict.UNKNOWN));

        // This is the counterexample: codehash is IDENTICAL, yet authenticated
        // factory provenance is absent, and the economic asset has ZERO real ETH.
        assertEq(counterfeit.balance, 0);
        assertEq(ReservableConditionalETHReference(counterfeit).backingOf(1), 2 ether);
    }

    function test_ForgedProvenanceCanFundLiveLoanButNotHonorLiquidation() public {
        address counterfeit = _forgeConditionalWithFalseBalance();
        OECLCompositionGate forgedGate = _deployForgedGate(counterfeit);
        OECLPartitionedClaimWitness unpinned = new OECLPartitionedClaimWitness(address(forgedGate));

        // The existing loan's exact runtime-code check is satisfied because
        // counterfeit's code is literally the same as the real reference.
        address loanAddr = unpinned.deployLoan(counterfeit);
        PartitionedReserveLoanPoC loan = PartitionedReserveLoanPoC(payable(loanAddr));
        ReservableConditionalETHReference nft = ReservableConditionalETHReference(counterfeit);
        assertEq(nft.lockedBy(1, otherController, address(0)), 1.2 ether);

        PartitionedReserveLoanPoC.Offer memory o = PartitionedReserveLoanPoC.Offer({
            tokenId: 1,
            lender: lender,
            principal: 0.5 ether,
            payoff: 0.55 ether,
            collateral: 0.6 ether,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: 1 days,
            grace: 0,
            termsHash: keccak256("untrusted loan economic claim")
        });

        vm.startPrank(borrower);
        nft.approve(loanAddr, 1);
        uint256 id = loan.propose(o);
        vm.stopPrank();

        uint256 beforeBorrower = borrower.balance;
        vm.prank(lender);
        loan.fund{value: 0.5 ether}(id, o.termsHash);
        assertEq(borrower.balance, beforeBorrower + 0.5 ether,
            "real lender funds transferred to borrower");
        assertEq(nft.lockedBy(1, loanAddr, address(0)), 0.6 ether);
        assertEq(nft.lockedValue(1, address(0)), 1.8 ether);
        assertEq(nft.backingOf(1), 2 ether);
        assertEq(counterfeit.balance, 0);
        assertTrue(nft.isSolvent());

        PartitionedReserveLoanPoC.Loan memory l = loan.loanInfo(id);
        vm.warp(uint256(l.dueAt) + 1);
        OECLPartitionedClaimWitness.Evidence memory e = unpinned.assess(
            counterfeit, loanAddr, id,
            OECLPartitionedClaimWitness.Kind.PartitionedLiquidationNow
        );
        assertEq(uint256(e.verdict), uint256(OECLPartitionedClaimWitness.Verdict.ACCEPT),
            "false positive from untrusted factory provenance");

        // Despite positive witness and identical reference runtime, redemption
        // is impossible: totalBacked was forged at zero and no real ETH was held.
        vm.expectRevert();
        loan.liquidate(id);
        assertEq(loan.credits(lender), 0);
        assertEq(loan.totalCredits(), 0);
        assertEq(nft.lockedBy(1, loanAddr, address(0)), 0.6 ether,
            "failed atomic liquidation must not release a lock");
        assertEq(uint256(genuinePin.inspectConditional(address(forgedGate), counterfeit)),
            uint256(OECLProvenancePin.Verdict.UNKNOWN));
    }

    function test_KnownGenuineFactoryDeploymentPassesPinnedProfileAdmission() public {
        address honest = genuineGate.deployConditionalAsset();
        assertEq(uint256(genuinePin.inspectConditional(address(genuineGate), honest)),
            uint256(OECLProvenancePin.Verdict.ADMIT_PROFILE));
        assertEq(uint256(genuinePin.inspectConditional(address(genuineGate), address(0xBAD))),
            uint256(OECLProvenancePin.Verdict.UNKNOWN));
        assertEq(address(honest).balance, 0); // a true newly deployed NFT has zero liabilities
        assertTrue(ReservableConditionalETHReference(honest).isSolvent());
    }
}
