// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IERC8060Reservable.sol";

interface IBilateralReserveNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title BilateralTimeboundReserve
/// @notice Experimental *accounting-only* reservations requiring explicit
///         acceptance by the protected beneficiary. No debt settlement, ETH
///         payment, liquidation, arbitration or beneficiary payout is supplied.
/// @dev Both sides agree to a hard expiry. After expiry anyone can release the
///      lock; before expiry ONLY the beneficiary can release it. Owners cannot
///      cancel an accepted commitment. This is an application-layer spender,
///      NOT a change to the six-function IERC8060Reservable interface.
///      Not audited or approved for custody of real funds.
contract BilateralTimeboundReserve is ReentrancyGuard {
    uint256 public constant MAX_DURATION = 365 days;
    address public constant ETH_ASSET = address(0);
    IERC8060Reservable public immutable reservable;

    enum Phase {
        Undefined,
        Proposed,
        Active,
        ReleasedEarly,
        ReleasedExpired,
        Cancelled,
        Rejected
    }

    struct Agreement {
        uint256 tokenId;
        uint256 amount;
        uint64 deadline;
        address proposer;
        address beneficiary;
        bytes32 termsHash;
        Phase phase;
    }

    uint256 public nextAgreementId = 1;
    mapping(uint256 => Agreement) public agreements;

    event AgreementProposed(
        uint256 indexed agreementId,
        uint256 indexed tokenId,
        address indexed beneficiary,
        address proposer,
        uint256 amount,
        uint64 deadline,
        bytes32 termsHash
    );
    event AgreementAccepted(uint256 indexed agreementId, address indexed beneficiary);
    event AgreementCancelled(uint256 indexed agreementId);
    event AgreementRejected(uint256 indexed agreementId);
    event AgreementReleased(uint256 indexed agreementId, bool byExpiry);

    constructor(address reservable_) {
        require(reservable_ != address(0), "invalid reservable");
        reservable = IERC8060Reservable(reservable_);
    }

    /// @notice An owner offers immutable terms. No value is locked at proposal.
    /// @dev The beneficiary must verify the document/terms behind termsHash.
    ///      A dishonest proposer cannot bind a beneficiary without acceptance.
    function propose(
        uint256 tokenId,
        uint256 amount,
        address beneficiary,
        uint64 deadline,
        bytes32 termsHash
    ) external nonReentrant returns (uint256 agreementId) {
        require(IBilateralReserveNFT(address(reservable)).ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(amount > 0, "zero amount");
        require(beneficiary != address(0) && beneficiary != msg.sender, "invalid beneficiary");
        require(termsHash != bytes32(0), "empty terms");
        require(uint256(deadline) > block.timestamp, "deadline passed");
        require(uint256(deadline) <= block.timestamp + MAX_DURATION, "duration too long");

        agreementId = nextAgreementId++;
        agreements[agreementId] = Agreement({
            tokenId: tokenId,
            amount: amount,
            deadline: deadline,
            proposer: msg.sender,
            beneficiary: beneficiary,
            termsHash: termsHash,
            phase: Phase.Proposed
        });

        emit AgreementProposed(agreementId, tokenId, beneficiary, msg.sender, amount, deadline, termsHash);
    }

    /// @notice The beneficiary accepts the SAME immutable hash, token, amount,
    ///         and expiry; an approved spender allocation is then locked.
    /// @dev The owner must previously call NFT.approveReserve(
    ///      tokenId, address(this), address(0), aggregate ceiling).
    ///      If the token transferred, the old proposal is not executable.
    function accept(uint256 agreementId, bytes32 expectedTermsHash) external nonReentrant {
        Agreement storage a = agreements[agreementId];
        require(a.phase == Phase.Proposed, "not proposed");
        require(msg.sender == a.beneficiary, "not beneficiary");
        require(expectedTermsHash == a.termsHash, "terms mismatch");
        require(block.timestamp < uint256(a.deadline), "deadline passed");
        require(IBilateralReserveNFT(address(reservable)).ownerOf(a.tokenId) == a.proposer, "owner changed");

        a.phase = Phase.Active; // effects first; revert rolls back if allocation fails
        reservable.reserveValue(a.tokenId, ETH_ASSET, a.amount);
        emit AgreementAccepted(agreementId, msg.sender);
    }

    /// @notice Proposal withdrawal is allowed only before acceptance, because
    ///         no protected commitment exists prior to a beneficiary's consent.
    function cancelPending(uint256 agreementId) external nonReentrant {
        Agreement storage a = agreements[agreementId];
        require(a.phase == Phase.Proposed, "not proposed");
        require(msg.sender == a.proposer, "not proposer");
        a.phase = Phase.Cancelled;
        emit AgreementCancelled(agreementId);
    }

    function rejectPending(uint256 agreementId) external nonReentrant {
        Agreement storage a = agreements[agreementId];
        require(a.phase == Phase.Proposed, "not proposed");
        require(msg.sender == a.beneficiary, "not beneficiary");
        a.phase = Phase.Rejected;
        emit AgreementRejected(agreementId);
    }

    /// @notice The beneficiary may voluntarily waive its outstanding
    ///         reservation before the pre-agreed expiry. Owner cannot.
    /// @dev No payment is made and this is NOT evidence of a settled debt.
    function releaseEarly(uint256 agreementId) external nonReentrant {
        Agreement storage a = agreements[agreementId];
        require(a.phase == Phase.Active, "not active");
        require(msg.sender == a.beneficiary, "not beneficiary");
        a.phase = Phase.ReleasedEarly;
        reservable.releaseValue(a.tokenId, ETH_ASSET, a.amount);
        emit AgreementReleased(agreementId, false);
    }

    /// @notice Permissionless exit at the *bilaterally accepted* fixed expiry.
    ///         This returns ETH to the NFT's AVAILABLE accounting, not to an
    ///         arbitrary party. It must be called by a transaction (no cron).
    function releaseExpired(uint256 agreementId) external nonReentrant {
        Agreement storage a = agreements[agreementId];
        require(a.phase == Phase.Active, "not active");
        require(block.timestamp >= uint256(a.deadline), "deadline not reached");
        a.phase = Phase.ReleasedExpired;
        reservable.releaseValue(a.tokenId, ETH_ASSET, a.amount);
        emit AgreementReleased(agreementId, true);
    }
}
