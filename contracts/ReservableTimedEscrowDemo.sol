// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

interface ITokenOwnerView {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract ReservableTimedEscrowDemo {
    IERC8060Reservable public immutable reservable;

    struct Agreement {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address beneficiary;
        uint64 deadline;
        bool active;
    }

    uint256 public nextId;
    mapping(uint256 => Agreement) public agreements;

    constructor(address reservable_) {
        require(reservable_ != address(0), "invalid contract");
        reservable = IERC8060Reservable(reservable_);
    }

    function createEscrow(
        uint256 tokenId,
        address asset,
        uint256 amount,
        address beneficiary,
        uint64 deadline
    ) external returns (uint256 id) {
        require(
            ITokenOwnerView(address(reservable)).ownerOf(tokenId)
                == msg.sender,
            "not NFT owner"
        );
        require(beneficiary != address(0), "invalid beneficiary");
        require(amount > 0, "zero amount");
        require(deadline > block.timestamp, "invalid deadline");

        reservable.reserveValue(tokenId, asset, amount);

        id = nextId++;
        agreements[id] = Agreement(
            tokenId, asset, amount, beneficiary, deadline, true
        );
    }

    function releaseByBeneficiary(uint256 id) external {
        Agreement storage a = agreements[id];
        require(msg.sender == a.beneficiary, "not beneficiary");
        _release(a);
    }

    function releaseAfterDeadline(uint256 id) external {
        Agreement storage a = agreements[id];
        require(a.active, "inactive");
        require(block.timestamp >= a.deadline, "not expired");
        _release(a);
    }

    function _release(Agreement storage a) internal {
        require(a.active, "inactive");
        a.active = false;
        reservable.releaseValue(a.tokenId, a.asset, a.amount);
    }
}
