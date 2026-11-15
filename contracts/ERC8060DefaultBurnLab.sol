// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC8060DefaultSaleLab.sol";

/// @notice Experimental liquidation by NFT burn.
/// @dev The borrower opts in by pledging the NFT here.
///      The NFT is destroyed if the burn fallback is used.
contract ERC8060DefaultBurnLab is ERC8060DefaultSaleLab {
    uint256 public constant BURN_GRACE_PERIOD = 1 days;

    event DefaultBurned(
        uint256 indexed loanId,
        uint256 recovered,
        uint256 lenderPaid,
        uint256 borrowerSurplus
    );

    constructor(address nft_) ERC8060DefaultSaleLab(nft_) {}

    // The NFT contract sends redemption ETH to its current owner,
    // which is this vault.
    receive() external payable {
        require(msg.sender == address(nft), "only NFT redemption");
    }

    function burnDefaultedNFT(uint256 id) external nonReentrant {
        Loan storage l = loans[id];

        require(l.status == Status.Funded, "not funded");
        require(
            block.timestamp >
                uint256(l.repayDeadline) + BURN_GRACE_PERIOD,
            "grace period active"
        );
        require(
            nft.ownerOf(l.tokenId) == address(this),
            "NFT not held"
        );

        uint256 quoted = valueToken.valueOf(l.tokenId);
        require(quoted >= l.principal, "insufficient backing");

        // State changes before external redemption.
        l.status = Status.Liquidated;
        tokenOnLoan[l.tokenId] = false;

        uint256 balanceBefore = address(this).balance;

        // ERC8060 burn: the vault owns the NFT and receives ETH.
        valueToken.burn(l.tokenId);

        uint256 recovered = address(this).balance - balanceBefore;

        // Do not trust a valueOf quote without verifying payment.
        require(recovered == quoted, "redemption mismatch");

        credits[l.lender] += l.principal;
        credits[l.borrower] += recovered - l.principal;

        emit DefaultBurned(
            id,
            recovered,
            l.principal,
            recovered - l.principal
        );
    }
}