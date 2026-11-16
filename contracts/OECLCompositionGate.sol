// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./reference/ERC8060NativeETHReference.sol";
import "./reference/ReservableConditionalETHReference.sol";
import "./BilateralTimeboundReserve.sol";
import "./ReservableRepaymentLoanDemo.sol";
import "./CustodiedCollateralLoanPoC.sol";

/// @title OECLCompositionGate
/// @notice EXPERIMENTAL admission gate, not an economic safety oracle or ERC.
/// @dev Creates supported assets and applications using their REAL constructors.
///      It NEVER accepts a caller-supplied collection or app as 'canonical'.
///      Trust in this gate's own deployment/provenance and audited code is still
///      required. Its verdicts are bounded capability admission checks, not
///      proofs that borrowers will repay, buyers will appear, or funds are safe.
///      Not audited and never for use with real user funds.
contract OECLCompositionGate {
    enum AssetProfile {
        Unrecognized,
        StrictRedeemableETH,
        ConditionalReservableETH
    }

    enum AppProfile {
        Unrecognized,
        BilateralAccounting,
        RepaymentOnly,
        CustodialLiquidation
    }

    enum Capability {
        ReserveAccounting,
        OwnerWithdrawAvailable,
        StrictOwnerBurn,
        CreditorCreditUponActualRepayment,
        CreditorDefaultRecoveryPath
    }

    enum Verdict { UNKNOWN, REJECT, ACCEPT }

    enum Reason {
        Compatible,
        UnrecognizedAsset,
        UnrecognizedApplication,
        WrongAsset,
        UnsupportedCapability,
        AssetInsolvent,
        NoLiveFundedLoan,
        CollateralNotCustodied,
        InsufficientBacking
    }

    mapping(address => AssetProfile) public assetProfiles;
    mapping(address => AppProfile) public applicationProfiles;
    mapping(address => address) public applicationAssets;

    event CanonicalAssetCreated(address indexed asset, AssetProfile indexed profile);
    event CanonicalApplicationCreated(
        address indexed application, address indexed asset, AppProfile indexed profile
    );
    event AssessmentReceipt(
        address indexed asset, address indexed application, Capability indexed requested,
        uint256 loanId, Verdict verdict, Reason reason
    );

    /// @dev Uses CREATE + the linked Solidity constructor. No external registry
    ///      admin, importer, or 'verify codehash' shortcut exists.
    function deployStrictAsset() external returns (address asset) {
        asset = address(new ERC8060NativeETHReference());
        assetProfiles[asset] = AssetProfile.StrictRedeemableETH;
        emit CanonicalAssetCreated(asset, AssetProfile.StrictRedeemableETH);
    }

    function deployConditionalAsset() external returns (address asset) {
        asset = address(new ReservableConditionalETHReference());
        assetProfiles[asset] = AssetProfile.ConditionalReservableETH;
        emit CanonicalAssetCreated(asset, AssetProfile.ConditionalReservableETH);
    }

    function deployBilateralAccounting(address asset) external returns (address app) {
        require(assetProfiles[asset] == AssetProfile.ConditionalReservableETH,
                "conditional NFT required");
        app = address(new BilateralTimeboundReserve(asset));
        _register(app, asset, AppProfile.BilateralAccounting);
    }

    function deployRepaymentOnly(address asset) external returns (address app) {
        require(assetProfiles[asset] == AssetProfile.ConditionalReservableETH,
                "conditional NFT required");
        app = address(new ReservableRepaymentLoanDemo(asset));
        _register(app, asset, AppProfile.RepaymentOnly);
    }

    function deployCustodialLiquidator(address asset) external returns (address app) {
        require(assetProfiles[asset] == AssetProfile.StrictRedeemableETH,
                "strict NFT required");
        app = address(new CustodiedCollateralLoanPoC(asset));
        _register(app, asset, AppProfile.CustodialLiquidation);
    }

    function _register(address app, address asset, AppProfile profile) private {
        applicationProfiles[app] = profile;
        applicationAssets[app] = asset;
        emit CanonicalApplicationCreated(app, asset, profile);
    }

    /// @notice Evaluates only specified capabilities of canonical components.
    /// @dev UNKNOWN and REJECT are NOT acceptable for value-sensitive admission.
    ///      ACCEPT means 'supported structural path under declared assumptions',
    ///      never 'all future economic outcomes proven safe'.
    function assess(address asset, address app, Capability requested, uint256 loanId)
        public view returns (Verdict verdict, Reason reason)
    {
        AssetProfile profile = assetProfiles[asset];
        if (profile == AssetProfile.Unrecognized) {
            return (Verdict.UNKNOWN, Reason.UnrecognizedAsset);
        }

        AppProfile appProfile = applicationProfiles[app];
        if (app != address(0)) {
            if (appProfile == AppProfile.Unrecognized) {
                return (Verdict.UNKNOWN, Reason.UnrecognizedApplication);
            }
            if (applicationAssets[app] != asset) {
                return (Verdict.REJECT, Reason.WrongAsset);
            }
        }

        bool solvent = profile == AssetProfile.StrictRedeemableETH
            ? ERC8060NativeETHReference(asset).isSolvent()
            : ReservableConditionalETHReference(asset).isSolvent();
        if (!solvent) return (Verdict.REJECT, Reason.AssetInsolvent);

        if (requested == Capability.ReserveAccounting) {
            bool compatible = profile == AssetProfile.ConditionalReservableETH
                && (app == address(0)
                    || appProfile == AppProfile.BilateralAccounting
                    || appProfile == AppProfile.RepaymentOnly);
            return _staticVerdict(compatible);
        }

        if (requested == Capability.OwnerWithdrawAvailable) {
            return _staticVerdict(profile == AssetProfile.ConditionalReservableETH
                                  && app == address(0));
        }

        if (requested == Capability.StrictOwnerBurn) {
            return _staticVerdict(profile == AssetProfile.StrictRedeemableETH
                                  && app == address(0));
        }

        if (requested == Capability.CreditorCreditUponActualRepayment) {
            return _staticVerdict(profile == AssetProfile.ConditionalReservableETH
                                  && appProfile == AppProfile.RepaymentOnly);
        }

        if (requested == Capability.CreditorDefaultRecoveryPath) {
            if (profile != AssetProfile.StrictRedeemableETH
                || appProfile != AppProfile.CustodialLiquidation) {
                return (Verdict.REJECT, Reason.UnsupportedCapability);
            }
            return _assessRecovery(asset, app, loanId);
        }

        return (Verdict.REJECT, Reason.UnsupportedCapability);
    }

    function _staticVerdict(bool supported) private pure returns (Verdict, Reason) {
        if (supported) return (Verdict.ACCEPT, Reason.Compatible);
        return (Verdict.REJECT, Reason.UnsupportedCapability);
    }

    function _assessRecovery(address asset, address app, uint256 id)
        private view returns (Verdict, Reason)
    {
        if (id == 0) return (Verdict.REJECT, Reason.NoLiveFundedLoan);
        CustodiedCollateralLoanPoC loan = CustodiedCollateralLoanPoC(payable(app));
        CustodiedCollateralLoanPoC.Loan memory l = loan.loanInfo(id);

        bool live = l.state == CustodiedCollateralLoanPoC.State.Active
            || l.state == CustodiedCollateralLoanPoC.State.Defaulted
            || l.state == CustodiedCollateralLoanPoC.State.Disputed
            || l.state == CustodiedCollateralLoanPoC.State.SaleOpen;
        if (!live || l.lender == address(0) || l.payoff <= l.repaid) {
            return (Verdict.REJECT, Reason.NoLiveFundedLoan);
        }

        if (ERC8060NativeETHReference(asset).ownerOf(l.tokenId) != app) {
            return (Verdict.REJECT, Reason.CollateralNotCustodied);
        }

        uint256 value = ERC8060NativeETHReference(asset).valueOf(l.tokenId);
        if (value != l.redemptionFloor || value < l.payoff - l.repaid
            || !loan.isCreditSolvent()) {
            return (Verdict.REJECT, Reason.InsufficientBacking);
        }
        return (Verdict.ACCEPT, Reason.Compatible);
    }

    /// @notice Creates a chain receipt of this gate's instantaneous assessment.
    /// @dev Not a receipt of Foundry tests, third-party audits or future liveness.
    function recordAssessment(address asset, address app, Capability requested, uint256 loanId)
        external returns (Verdict verdict, Reason reason)
    {
        (verdict, reason) = assess(asset, app, requested, loanId);
        emit AssessmentReceipt(asset, app, requested, loanId, verdict, reason);
    }
}
