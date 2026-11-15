// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

interface ILoanNFTOwner {
    function ownerOf(uint256 id) external view returns (address);
}

contract ReservableRepaymentLoanDemo {
    IERC8060Reservable public immutable reservable;

    struct Loan {
        uint256 tokenId;
        uint256 collateral;
        uint256 principal;
        address borrower;
        address lender;
        uint64 deadline;
        bool funded;
        bool repaid;
        bool cancelled;
    }

    uint256 public nextId;
    mapping(uint256 => Loan) public loans;
    mapping(address => uint256) public lenderCredits;

    constructor(address nft) {
        require(nft != address(0), "invalid NFT");
        reservable = IERC8060Reservable(nft);
    }

    function createLoan(
        uint256 tokenId,
        uint256 collateral,
        uint256 principal,
        address lender,
        uint64 deadline
    ) external returns (uint256 id) {
        require(
            ILoanNFTOwner(address(reservable)).ownerOf(tokenId)
                == msg.sender,
            "not NFT owner"
        );
        require(collateral > 0 && principal > 0, "zero amount");
        require(lender != address(0), "invalid lender");
        require(deadline > block.timestamp, "invalid deadline");

        reservable.reserveValue(tokenId, address(0), collateral);

        id = nextId++;
        loans[id] = Loan(
            tokenId, collateral, principal, msg.sender,
            lender, deadline, false, false, false
        );
    }

    function fundLoan(uint256 id) external payable {
        Loan storage l = loans[id];
        require(!l.funded && !l.cancelled, "not fundable");
        require(msg.sender == l.lender, "not lender");
        require(block.timestamp < l.deadline, "expired");
        require(msg.value == l.principal, "wrong amount");
        require(
            ILoanNFTOwner(address(reservable)).ownerOf(l.tokenId)
                == l.borrower,
            "NFT transferred"
        );

        l.funded = true;
        (bool ok, ) = payable(l.borrower).call{value: msg.value}("");
        require(ok, "funding failed");
    }

    function repayLoan(uint256 id) external payable {
        Loan storage l = loans[id];
        require(l.funded && !l.repaid, "not repayable");
        require(msg.value == l.principal, "full repayment required");

        l.repaid = true;
        lenderCredits[l.lender] += msg.value;

        reservable.releaseValue(
            l.tokenId, address(0), l.collateral
        );
    }

    function cancelUnfunded(uint256 id) external {
        Loan storage l = loans[id];
        require(!l.funded && !l.cancelled, "cannot cancel");
        require(
            msg.sender == l.borrower ||
            msg.sender == l.lender ||
            block.timestamp >= l.deadline,
            "not authorized"
        );
        l.cancelled = true;
        reservable.releaseValue(
            l.tokenId, address(0), l.collateral
        );
    }

    function withdrawRepayment() external {
        uint256 amount = lenderCredits[msg.sender];
        require(amount > 0, "nothing to withdraw");
        lenderCredits[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
    }
}