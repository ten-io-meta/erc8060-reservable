// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OECLCompositionGate.sol";
import "./PartitionedReserveLoanPoC.sol";
import "./IReserveControllerView.sol";

/// @notice Closed-world creator of the exact, non-upgradeable partitioned loan.
/// @dev Cannot import arbitrary app addresses or self-report capabilities.
contract OECLPartitionedLoanFactory {
    OECLCompositionGate public immutable gate;
    mapping(address => address) public boundAsset;

    event PartitionedLoanDeployed(address indexed application, address indexed asset);

    constructor(address gate_) {
        require(gate_ != address(0) && gate_.code.length != 0, "invalid gate");
        gate = OECLCompositionGate(gate_);
    }

    function deploy(address asset) external returns (address app) {
        require(gate.assetProfiles(asset) ==
            OECLCompositionGate.AssetProfile.ConditionalReservableETH,
            "conditional asset required");
        app = address(new PartitionedReserveLoanPoC(asset, address(gate)));
        boundAsset[app] = asset;
        emit PartitionedLoanDeployed(app, asset);
    }
}

/// @title OECLPartitionedClaimWitness
/// @notice Experimental onchain evidence of limited, current execution ability.
/// @dev ACCEPT is NOT a proof of economic safety, future liveness, independent
///      audits or arbitrary protocol compatibility. A current-state snapshot
///      cannot stop repayment or changed state in a later transaction.
///      Trust roots: the REAL deployment/constructor initialization of this
///      witness, the OECL gate and its factories, and the canonical source code.
///      Never use this research prototype with real funds.
contract OECLPartitionedClaimWitness {
    enum Kind { AccountingSurface, PartitionedLiquidationNow, StrictBurnProfile }
    enum Verdict { UNKNOWN, REJECT, ACCEPT }
    enum Reason {
        Compatible,
        UnrecognizedAsset,
        UnrecognizedApp,
        WrongAsset,
        WrongProfile,
        InsolventAsset,
        NotFunded,
        NotYetExecutable,
        MissingCustody,
        InvalidLoanBinding,
        InvalidEconomicState,
        InsolventCredits,
        ControllerAllocationMismatch
    }

    struct Evidence {
        Verdict verdict;
        Reason reason;
        address asset;
        address application;
        uint256 loanId;
        uint256 tokenId;
        address creditor;
        uint256 collateral;
        uint256 payoff;
        uint256 backing;
        uint256 locked;
        uint256 controllerLocked;
        uint256 otherLocked;
        uint256 available;
        uint256 dueAfterGrace;
        uint256 observedBlock;
        bytes32 evidenceHash;
    }

    OECLCompositionGate public immutable gate;
    OECLPartitionedLoanFactory public immutable loanFactory;

    event EvidenceReceipt(
        address indexed asset,
        address indexed application,
        uint256 indexed loanId,
        Kind requested,
        Verdict verdict,
        Reason reason,
        bytes32 evidenceHash
    );

    /// @dev The factory is actually created by this witness constructor.
    ///      Anyone supplying arbitrary NFT or app addresses cannot register
    ///      them. The authentic witness deployment is an external trust root.
    constructor(address gate_) {
        require(gate_ != address(0) && gate_.code.length != 0, "invalid gate");
        gate = OECLCompositionGate(gate_);
        loanFactory = new OECLPartitionedLoanFactory(gate_);
    }

    function deployLoan(address asset) external returns (address app) {
        app = loanFactory.deploy(asset);
    }

    function assess(address asset, address app, uint256 loanId, Kind requested)
        public view returns (Evidence memory e)
    {
        e.asset = asset;
        e.application = app;
        e.loanId = loanId;
        e.observedBlock = block.number;

        OECLCompositionGate.AssetProfile profile = gate.assetProfiles(asset);
        if (profile == OECLCompositionGate.AssetProfile.Unrecognized) {
            return _finish(e, requested, Verdict.UNKNOWN, Reason.UnrecognizedAsset);
        }

        if (requested == Kind.StrictBurnProfile) {
            if (app != address(0) || profile !=
                OECLCompositionGate.AssetProfile.StrictRedeemableETH) {
                return _finish(e, requested, Verdict.REJECT, Reason.WrongProfile);
            }
            if (!ERC8060NativeETHReference(asset).isSolvent()) {
                return _finish(e, requested, Verdict.REJECT, Reason.InsolventAsset);
            }
            return _finish(e, requested, Verdict.ACCEPT, Reason.Compatible);
        }

        if (profile != OECLCompositionGate.AssetProfile.ConditionalReservableETH) {
            return _finish(e, requested, Verdict.REJECT, Reason.WrongProfile);
        }
        ReservableConditionalETHReference nft = ReservableConditionalETHReference(asset);
        if (!nft.isSolvent()) {
            return _finish(e, requested, Verdict.REJECT, Reason.InsolventAsset);
        }

        if (requested == Kind.AccountingSurface) {
            address bound = loanFactory.boundAsset(app);
            if (bound != address(0) && bound != asset) {
                return _finish(e, requested, Verdict.REJECT, Reason.WrongAsset);
            }
            if (app != address(0) && bound != asset) {
                (OECLCompositionGate.Verdict oldVerdict, ) = gate.assess(
                    asset, app, OECLCompositionGate.Capability.ReserveAccounting, 0
                );
                if (oldVerdict == OECLCompositionGate.Verdict.UNKNOWN) {
                    return _finish(e, requested, Verdict.UNKNOWN, Reason.UnrecognizedApp);
                }
                if (oldVerdict != OECLCompositionGate.Verdict.ACCEPT) {
                    return _finish(e, requested, Verdict.REJECT, Reason.WrongAsset);
                }
            }
            return _finish(e, requested, Verdict.ACCEPT, Reason.Compatible);
        }

        address registeredAsset = loanFactory.boundAsset(app);
        if (registeredAsset == address(0)) {
            return _finish(e, requested, Verdict.UNKNOWN, Reason.UnrecognizedApp);
        }
        if (registeredAsset != asset) {
            return _finish(e, requested, Verdict.REJECT, Reason.WrongAsset);
        }
        PartitionedReserveLoanPoC loan = PartitionedReserveLoanPoC(payable(app));
        if (address(loan.nft()) != asset || address(loan.gate()) != address(gate)) {
            return _finish(e, requested, Verdict.REJECT, Reason.InvalidLoanBinding);
        }
        if (loanId == 0 || loanId >= loan.nextLoanId()) {
            return _finish(e, requested, Verdict.REJECT, Reason.NotFunded);
        }

        PartitionedReserveLoanPoC.Loan memory l = loan.loanInfo(loanId);
        e.tokenId = l.tokenId;
        e.creditor = l.lender;
        e.collateral = l.collateral;
        e.payoff = l.payoff;
        e.dueAfterGrace = uint256(l.dueAt) + l.grace;
        if (l.state != PartitionedReserveLoanPoC.State.Active ||
            l.lender == address(0) || l.dueAt == 0) {
            return _finish(e, requested, Verdict.REJECT, Reason.NotFunded);
        }
        if (loan.activeTokenLoan(l.tokenId) != loanId ||
            nft.ownerOf(l.tokenId) != app) {
            return _finish(e, requested, Verdict.REJECT, Reason.MissingCustody);
        }
        e.backing = nft.backingOf(l.tokenId);
        e.locked = nft.lockedValue(l.tokenId, address(0));
        // Read the authoritative NFT ledger. A controller's own loanInfo and
        // the aggregate lockedValue CANNOT prove which spender owns the lock.
        e.controllerLocked = IReserveControllerView(asset).lockedBy(
            l.tokenId, app, address(0)
        );
        e.available = nft.availableValue(l.tokenId, address(0));
        if (l.principal == 0 || l.payoff < l.principal ||
            l.collateral < l.payoff || e.backing < l.collateral ||
            e.locked < l.collateral || e.backing < e.locked ||
            e.available != e.backing - e.locked) {
            return _finish(e, requested, Verdict.REJECT, Reason.InvalidEconomicState);
        }
        if (e.controllerLocked > e.locked) {
            return _finish(e, requested, Verdict.REJECT, Reason.ControllerAllocationMismatch);
        }
        e.otherLocked = e.locked - e.controllerLocked;
        if (e.controllerLocked != l.collateral) {
            return _finish(e, requested, Verdict.REJECT, Reason.ControllerAllocationMismatch);
        }
        if (!loan.isCreditSolvent()) {
            return _finish(e, requested, Verdict.REJECT, Reason.InsolventCredits);
        }
        if (block.timestamp <= e.dueAfterGrace) {
            return _finish(e, requested, Verdict.REJECT, Reason.NotYetExecutable);
        }
        return _finish(e, requested, Verdict.ACCEPT, Reason.Compatible);
    }

    /// @notice Live snapshot, NOT a durable credential for future settlement.
    ///      Re-assess in the settlement transaction before relying on evidence.
    function record(address asset, address app, uint256 loanId, Kind requested)
        external returns (Evidence memory e)
    {
        e = assess(asset, app, loanId, requested);
        emit EvidenceReceipt(
            asset, app, loanId, requested, e.verdict, e.reason, e.evidenceHash
        );
    }

    function _finish(Evidence memory e, Kind requested, Verdict v, Reason r)
        private view returns (Evidence memory)
    {
        e.verdict = v;
        e.reason = r;
        e.evidenceHash = keccak256(abi.encode(
            block.chainid, address(this), block.number, block.timestamp,
            requested, e
        ));
        return e;
    }
}
