// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../CustodiedCollateralLoanPoC.sol";

interface IProbeMintableNFT {
    function mint() external payable returns (uint256);
    function approve(address to, uint256 id) external;
}

/// @notice Laboratory-only smart-contract borrower that can reject funding
///         or attempt a callback into the loan during principal delivery.
contract LoanBorrowerReceiverProbe is IERC721Receiver {
    IProbeMintableNFT public immutable nft;
    CustodiedCollateralLoanPoC public immutable loan;
    bool public rejectETH = true;
    bool public attackCallback;
    bool public callbackBlocked;
    uint256 public loanId;

    constructor(address nft_, address loan_) {
        nft = IProbeMintableNFT(nft_);
        loan = CustodiedCollateralLoanPoC(payable(loan_));
    }

    function configure(bool reject_, bool callback_) external {
        rejectETH = reject_;
        attackCallback = callback_;
    }

    function mintAndOffer(CustodiedCollateralLoanPoC.Offer calldata offer) external payable {
        uint256 id = nft.mint{value: msg.value}();
        require(id == offer.tokenId, "wrong token id");
        nft.approve(address(loan), id);
        loanId = loan.propose(offer);
    }

    receive() external payable {
        require(!rejectETH, "borrower rejects ETH");
        if (attackCallback) {
            (bool success, ) = address(loan).call(
                abi.encodeWithSignature("cancelUnfunded(uint256,address)", loanId, address(this))
            );
            callbackBlocked = !success;
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external pure override returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
