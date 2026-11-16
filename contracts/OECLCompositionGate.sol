// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./reference/ERC8060NativeETHReference.sol";
import "./reference/ReservableConditionalETHReference.sol";
import "./BilateralTimeboundReserve.sol";
import "./ReservableRepaymentLoanDemo.sol";
import "./CustodiedCollateralLoanPoC.sol";

/// @notice EXPERIMENTAL trusted deployment roots. No arbitrary registrations.
/// @dev Their own deployment provenance must be authenticated independently.
///      A codehash alone cannot exclude forged constructor/initial storage.
///      Each new reference is instantiated using the linked real constructor.
contract OECLCanonicalAssetFactory {
    mapping(address => uint8) public assetProfiles; // strict=1, conditional=2

    function deployStrictAsset() external returns (address asset) {
        asset = address(new ERC8060NativeETHReference());
        assetProfiles[asset] = 1;
    }

    function deployConditionalAsset() external returns (address asset) {
        asset = address(new ReservableConditionalETHReference());
        assetProfiles[asset] = 2;
    }
}

/// @notice Only creates applications bound to conditional ETH-backed NFTs.
contract OECLAccountingAppFactory {
    address public assetFactory;
    mapping(address => uint8) public profiles; // bilateral=1, repayment=2
    mapping(address => address) public boundAssets;

    constructor(address assets) {
        require(assets != address(0) && assets.code.length != 0, "invalid root");
        assetFactory = assets;
    }

    function deployBilateralAccounting(address asset) external returns (address app) {
        require(OECLCanonicalAssetFactory(assetFactory).assetProfiles(asset) == 2,
                "conditional NFT required");
        app = address(new BilateralTimeboundReserve(asset));
        profiles[app] = 1;
        boundAssets[app] = asset;
    }

    function deployRepaymentOnly(address asset) external returns (address app) {
        require(OECLCanonicalAssetFactory(assetFactory).assetProfiles(asset) == 2,
                "conditional NFT required");
        app = address(new ReservableRepaymentLoanDemo(asset));
        profiles[app] = 2;
        boundAssets[app] = asset;
    }
}

/// @notice Only creates custodial-liquidation loans for the strict ETH profile.
contract OECLRecoveryAppFactory {
    address public assetFactory;
    mapping(address => bool) public knownLoans;
    mapping(address => address) public boundAssets;

    constructor(address assets) {
        require(assets != address(0) && assets.code.length != 0, "invalid root");
        assetFactory = assets;
    }

    function deployCustodialLiquidator(address asset) external returns (address app) {
        require(OECLCanonicalAssetFactory(assetFactory).assetProfiles(asset) == 1,
                "strict NFT required");
        app = address(new CustodiedCollateralLoanPoC(asset));
        knownLoans[app] = true;
        boundAssets[app] = asset;
    }
}

/// @title OECLCompositionGate
/// @notice Bounded ACCEPT/REJECT/UNKNOWN assessment of registered components.
/// @dev FACTORIES ARE TRUST ROOTS. Constructor verifies their compiled runtime
///      and their associations, but cannot prove correct constructor storage.
///      The factory addresses and gate itself MUST have independently authenticated
///      deployment provenance. No user funds; not audited; no ERC ABI changes.
///      This gate never imports external collections/apps by admin fiat.
contract OECLCompositionGate {
    enum AssetProfile { Unrecognized, StrictRedeemableETH, ConditionalReservableETH }
    enum AppProfile { Unrecognized, BilateralAccounting, RepaymentOnly, CustodialLiquidation }
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

    OECLCanonicalAssetFactory public immutable assets;
    OECLAccountingAppFactory public immutable accounting;
    OECLRecoveryAppFactory public immutable recovery;

    event CanonicalAssetCreated(address indexed asset, AssetProfile indexed profile);
    event CanonicalApplicationCreated(
        address indexed application, address indexed asset, AppProfile indexed profile
    );
    event AssessmentReceipt(
        address indexed asset, address indexed application, Capability indexed requested,
        uint256 loanId, Verdict verdict, Reason reason
    );

    constructor(address assetFactory_, address accountingFactory_, address recoveryFactory_) {
        require(assetFactory_ != address(0) && accountingFactory_ != address(0)
            && recoveryFactory_ != address(0), "zero factory");
        require(assetFactory_.codehash == keccak256(type(OECLCanonicalAssetFactory).runtimeCode),
                "untrusted asset factory code");
        require(accountingFactory_.codehash == keccak256(type(OECLAccountingAppFactory).runtimeCode),
                "untrusted accounting factory code");
        require(recoveryFactory_.codehash == keccak256(type(OECLRecoveryAppFactory).runtimeCode),
                "untrusted recovery factory code");
        assets = OECLCanonicalAssetFactory(assetFactory_);
        accounting = OECLAccountingAppFactory(accountingFactory_);
        recovery = OECLRecoveryAppFactory(recoveryFactory_);
        require(accounting.assetFactory() == assetFactory_
            && recovery.assetFactory() == assetFactory_, "factory association mismatch");
    }

    function assetProfiles(address asset) public view returns (AssetProfile) {
        return AssetProfile(assets.assetProfiles(asset));
    }

    function applicationProfiles(address app) public view returns (AppProfile) {
        uint8 acc = accounting.profiles(app);
        if (acc == 1) return AppProfile.BilateralAccounting;
        if (acc == 2) return AppProfile.RepaymentOnly;
        if (recovery.knownLoans(app)) return AppProfile.CustodialLiquidation;
        return AppProfile.Unrecognized;
    }

    function applicationAssets(address app) public view returns (address) {
        if (accounting.profiles(app) != 0) return accounting.boundAssets(app);
        if (recovery.knownLoans(app)) return recovery.boundAssets(app);
        return address(0);
    }

    /// @dev Convenience entrypoints: registration is performed ONLY by the
    ///      appropriate fixed-code factory, never from caller supplied claims.
    function deployStrictAsset() external returns (address asset) {
        asset = assets.deployStrictAsset();
        emit CanonicalAssetCreated(asset, AssetProfile.StrictRedeemableETH);
    }

    function deployConditionalAsset() external returns (address asset) {
        asset = assets.deployConditionalAsset();
        emit CanonicalAssetCreated(asset, AssetProfile.ConditionalReservableETH);
    }

    function deployBilateralAccounting(address asset) external returns (address app) {
        app = accounting.deployBilateralAccounting(asset);
        emit CanonicalApplicationCreated(app, asset, AppProfile.BilateralAccounting);
    }

    function deployRepaymentOnly(address asset) external returns (address app) {
        app = accounting.deployRepaymentOnly(asset);
        emit CanonicalApplicationCreated(app, asset, AppProfile.RepaymentOnly);
    }

    function deployCustodialLiquidator(address asset) external returns (address app) {
        app = recovery.deployCustodialLiquidator(asset);
        emit CanonicalApplicationCreated(app, asset, AppProfile.CustodialLiquidation);
    }

    /// @notice ACCEPT only a bounded structural capability, NEVER future repayment.
    ///      Unknown provenance must not be interpreted as acceptance.
    function assess(address asset, address app, Capability requested, uint256 loanId)
        public view returns (Verdict, Reason)
    {
        AssetProfile profile = assetProfiles(asset);
        if (profile == AssetProfile.Unrecognized) {
            return (Verdict.UNKNOWN, Reason.UnrecognizedAsset);
        }

        AppProfile appProfile = applicationProfiles(app);
        if (app != address(0)) {
            if (appProfile == AppProfile.Unrecognized) {
                return (Verdict.UNKNOWN, Reason.UnrecognizedApplication);
            }
            if (applicationAssets(app) != asset) {
                return (Verdict.REJECT, Reason.WrongAsset);
            }
        }

        bool solvent = profile == AssetProfile.StrictRedeemableETH
            ? ERC8060NativeETHReference(asset).isSolvent()
            : ReservableConditionalETHReference(asset).isSolvent();
        if (!solvent) return (Verdict.REJECT, Reason.AssetInsolvent);

        if (requested == Capability.ReserveAccounting) {
            return _staticVerdict(profile == AssetProfile.ConditionalReservableETH
                && (app == address(0)
                    || appProfile == AppProfile.BilateralAccounting
                    || appProfile == AppProfile.RepaymentOnly));
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

    /// @notice Onchain assessment receipt, NOT a test or audit certificate.
    function recordAssessment(address asset, address app, Capability requested, uint256 loanId)
        external returns (Verdict verdict, Reason reason)
    {
        (verdict, reason) = assess(asset, app, requested, loanId);
        emit AssessmentReceipt(asset, app, requested, loanId, verdict, reason);
    }
}
