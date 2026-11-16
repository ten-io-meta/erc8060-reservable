// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./reference/ReservableConditionalETHReference.sol";
import "./OECLCompositionGate.sol";

/// @title PartitionedReserveLoanPoC
/// @notice EXPERIMENTAL: real-ETH collateral recovery from ONLY this application's
///         reserved portion while preserving other applications' live locks.
/// @dev The lender obtains execution via actual NFT custody AND a controlled,
///      atomic release->owner withdrawal of ONLY this loan's own reservation.
///      Other locks are preserved. The six-function IERC8060Reservable ABI is
///      unchanged. Conditional profile only; this is NOT strict ERC-8060.
///      The provenance gate, its factories and their initial deployments MUST
///      be independently authenticated. No audit; never use real user funds.
contract PartitionedReserveLoanPoC is IERC721Receiver, ReentrancyGuard {
    address public constant ETH_ASSET = address(0);
    uint256 public constant MAX_FUNDING_WINDOW = 30 days;
    uint256 public constant MAX_LOAN_TERM = 365 days;
    uint256 public constant MAX_GRACE = 30 days;

    ReservableConditionalETHReference public immutable nft;
    OECLCompositionGate public immutable gate;

    enum State { Unknown, Proposed, Active, Repaid, Liquidated, Cancelled, NFTReturned }

    struct Loan {
        uint256 tokenId;
        address borrower;
        address lender;
        uint256 principal;
        uint256 payoff;
        uint256 collateral;
        uint64 fundingDeadline;
        uint64 term;
        uint64 grace;
        uint64 dueAt;
        bytes32 termsHash;
        State state;
    }

    struct Offer {
        uint256 tokenId;
        address lender;
        uint256 principal;
        uint256 payoff;
        uint256 collateral;
        uint64 fundingDeadline;
        uint64 term;
        uint64 grace;
        bytes32 termsHash;
    }

    uint256 public nextLoanId = 1;
    mapping(uint256 => Loan) private _loans;
    mapping(uint256 => uint256) public activeTokenLoan;
    mapping(address => uint256) public credits;
    uint256 public totalCredits;

    bool private expectingNFT;
    address private expectedFrom;
    uint256 private expectedToken;

    event Proposed(uint256 indexed loanId, uint256 indexed tokenId, uint256 collateral);
    event Funded(uint256 indexed loanId, uint256 amount, uint64 dueAt);
    event Repaid(uint256 indexed loanId, uint256 amount);
    event Liquidated(uint256 indexed loanId, uint256 redeemed, uint256 lenderAward, uint256 borrowerSurplus);
    event Cancelled(uint256 indexed loanId);
    event NFTReturned(uint256 indexed loanId, address indexed recipient);
    event CreditWithdrawn(address indexed creditor, address indexed recipient, uint256 amount);

    constructor(address nft_, address provenanceGate_) {
        require(nft_ != address(0) && provenanceGate_ != address(0), "zero component");
        require(nft_.codehash == keccak256(type(ReservableConditionalETHReference).runtimeCode),
                "untrusted conditional NFT");
        require(provenanceGate_.code.length > 0, "invalid gate");
        gate = OECLCompositionGate(provenanceGate_);
        require(gate.assetProfiles(nft_) == OECLCompositionGate.AssetProfile.ConditionalReservableETH,
                "not factory-recognized NFT");
        nft = ReservableConditionalETHReference(nft_);
        require(nft.isSolvent(), "insolvent NFT");
    }

    function loanInfo(uint256 id) external view returns (Loan memory) {
        return _loans[id];
    }

    function isCreditSolvent() external view returns (bool) {
        return address(this).balance >= totalCredits;
    }

    /// @notice Borrower transfers the NFT into temporary custody; existing
    ///         unrelated reservations survive. After custody transfer invalidates
    ///         stale permissions, the loan approves and reserves its OWN portion.
    function propose(Offer calldata o) external nonReentrant returns (uint256 id) {
        require(activeTokenLoan[o.tokenId] == 0, "token already in loan");
        require(nft.ownerOf(o.tokenId) == msg.sender, "not NFT owner");
        require(o.lender != address(0) && o.lender != msg.sender, "invalid lender");
        require(o.principal > 0 && o.payoff >= o.principal
                && o.collateral >= o.payoff, "undersecured loan");
        require(o.termsHash != bytes32(0), "terms required");
        require(uint256(o.fundingDeadline) > block.timestamp
                && uint256(o.fundingDeadline) <= block.timestamp + MAX_FUNDING_WINDOW,
                "funding deadline");
        require(o.term > 0 && o.term <= MAX_LOAN_TERM, "invalid term");
        require(o.grace <= MAX_GRACE, "invalid grace");
        require(nft.isSolvent(), "insolvent NFT");
        require(o.collateral <= nft.availableValue(o.tokenId, ETH_ASSET), "insufficient unreserved ETH");

        id = nextLoanId++;
        Loan storage l = _loans[id];
        l.tokenId = o.tokenId;
        l.borrower = msg.sender;
        l.lender = o.lender;
        l.principal = o.principal;
        l.payoff = o.payoff;
        l.collateral = o.collateral;
        l.fundingDeadline = o.fundingDeadline;
        l.term = o.term;
        l.grace = o.grace;
        l.termsHash = o.termsHash;
        l.state = State.Proposed;
        activeTokenLoan[o.tokenId] = id;

        expectingNFT = true;
        expectedFrom = msg.sender;
        expectedToken = o.tokenId;
        nft.safeTransferFrom(msg.sender, address(this), o.tokenId);
        expectingNFT = false;
        expectedFrom = address(0);
        expectedToken = 0;
        require(nft.ownerOf(o.tokenId) == address(this), "custody failed");

        nft.approveReserve(o.tokenId, address(this), ETH_ASSET, o.collateral);
        nft.reserveValue(o.tokenId, ETH_ASSET, o.collateral);
        require(nft.lockedValue(o.tokenId, ETH_ASSET) >= o.collateral, "lock missing");
        emit Proposed(id, o.tokenId, o.collateral);
    }

    /// @notice Exact real ETH funding, with explicit lender/terms consent.
    function fund(uint256 id, bytes32 agreedTermsHash) external payable nonReentrant {
        Loan storage l = _loans[id];
        require(l.state == State.Proposed, "not proposed");
        require(msg.sender == l.lender, "not lender");
        require(l.termsHash == agreedTermsHash, "terms mismatch");
        require(block.timestamp <= l.fundingDeadline, "funding expired");
        require(msg.value == l.principal, "wrong principal");
        require(nft.ownerOf(l.tokenId) == address(this), "collateral missing");
        require(nft.lockedValue(l.tokenId, ETH_ASSET) >= l.collateral, "lock missing");
        require(nft.isSolvent(), "insolvent NFT");
        l.state = State.Active;
        l.dueAt = uint64(block.timestamp + l.term);
        (bool sent, ) = payable(l.borrower).call{value: msg.value}("");
        require(sent, "borrower funding failed");
        emit Funded(id, msg.value, l.dueAt);
    }

    /// @notice Real full repayment before liquidation; allowed even after due.
    ///         A valid liquidation can win ordering. No forced offchain settlement.
    function repay(uint256 id) external payable nonReentrant {
        Loan storage l = _loans[id];
        require(l.state == State.Active, "not active");
        require(msg.value == l.payoff, "exact payoff required");
        l.state = State.Repaid;
        credits[l.lender] += msg.value;
        totalCredits += msg.value;
        _releaseOwnLock(l);
        emit Repaid(id, msg.value);
    }

    /// @notice After expiry: unlock ONLY this spender's reservation, then as
    ///         actual owner withdraw exactly that portion. Both operations are
    ///         one atomic transaction, and unrelated reservations stay locked.
    /// @dev No arbitrary ERC-721s or proxies accepted. If any payout or invariant
    ///      check fails, the whole operation reverts (including releaseValue).
    function liquidate(uint256 id) external nonReentrant {
        Loan storage l = _loans[id];
        require(l.state == State.Active, "not active");
        require(block.timestamp > uint256(l.dueAt) + l.grace, "still repayable");
        require(nft.ownerOf(l.tokenId) == address(this), "collateral missing");
        require(nft.isSolvent(), "insolvent NFT");

        uint256 beforeBacking = nft.backingOf(l.tokenId);
        uint256 beforeLocked = nft.lockedValue(l.tokenId, ETH_ASSET);
        uint256 beforeAvailable = nft.availableValue(l.tokenId, ETH_ASSET);
        require(beforeLocked >= l.collateral, "own lock missing");
        require(beforeBacking >= beforeLocked, "backing below obligations");

        l.state = State.Liquidated;
        uint256 beforeETH = address(this).balance;
        _releaseOwnLock(l);
        nft.withdrawAvailable(l.tokenId, l.collateral);
        uint256 received = address(this).balance - beforeETH;
        require(received == l.collateral, "wrong collateral payout");
        require(nft.lockedValue(l.tokenId, ETH_ASSET) == beforeLocked - l.collateral,
                "other reservations changed");
        require(nft.backingOf(l.tokenId) == beforeBacking - l.collateral,
                "wrong backing reduction");
        require(nft.availableValue(l.tokenId, ETH_ASSET) == beforeAvailable,
                "unreserved owner value changed");
        require(nft.isSolvent(), "backing became insolvent");

        credits[l.lender] += l.payoff;
        credits[l.borrower] += received - l.payoff;
        totalCredits += received;
        require(address(this).balance >= totalCredits, "credits insolvent");
        emit Liquidated(id, received, l.payoff, received - l.payoff);
    }

    function cancelUnfunded(uint256 id) external nonReentrant {
        Loan storage l = _loans[id];
        require(l.state == State.Proposed, "not proposed");
        require(msg.sender == l.borrower || block.timestamp > l.fundingDeadline,
                "not authorized");
        l.state = State.Cancelled;
        _releaseOwnLock(l);
        emit Cancelled(id);
    }

    /// @notice NFT is claimable separately: a rejecting ERC721 receiver must
    ///         never prevent real ETH creditors from receiving liquidation credits.
    function claimCollateral(uint256 id, address recipient) external nonReentrant {
        Loan storage l = _loans[id];
        require(l.state == State.Repaid || l.state == State.Liquidated
                || l.state == State.Cancelled, "NFT still encumbered by loan");
        require(msg.sender == l.borrower, "not borrower");
        require(recipient != address(0) && recipient != address(this), "invalid recipient");
        l.state = State.NFTReturned;
        activeTokenLoan[l.tokenId] = 0;
        nft.safeTransferFrom(address(this), recipient, l.tokenId);
        require(nft.ownerOf(l.tokenId) == recipient, "NFT transfer failed");
        emit NFTReturned(id, recipient);
    }

    function withdrawCredit(address payable recipient) external nonReentrant {
        require(recipient != address(0), "invalid recipient");
        uint256 amount = credits[msg.sender];
        require(amount != 0, "no credit");
        credits[msg.sender] = 0;
        totalCredits -= amount;
        (bool sent, ) = recipient.call{value: amount}("");
        require(sent, "ETH withdrawal failed");
        emit CreditWithdrawn(msg.sender, recipient, amount);
    }

    function _releaseOwnLock(Loan storage l) private {
        nft.releaseValue(l.tokenId, ETH_ASSET, l.collateral);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external view override returns (bytes4)
    {
        require(msg.sender == address(nft) && expectingNFT
                && operator == address(this) && from == expectedFrom
                && tokenId == expectedToken, "unsolicited NFT");
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {
        require(msg.sender == address(nft), "unexpected ETH sender");
    }
}
