// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

interface ITaskBondOwnerView {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract AgentTaskBondTimedDemo {
    IERC8060Reservable public immutable reservable;

    struct Bond {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address agent;
        address verifier;
        uint64 deadline;
        bool active;
    }

    uint256 public nextBondId;
    mapping(uint256 => Bond) public bonds;

    constructor(address reservable_) {
        require(reservable_ != address(0), "invalid reservable");
        reservable = IERC8060Reservable(reservable_);
    }

    function createBond(
        uint256 tokenId,
        address asset,
        uint256 amount,
        address agent,
        address verifier,
        uint64 deadline
    ) external returns (uint256 id) {
        require(
            ITaskBondOwnerView(address(reservable)).ownerOf(tokenId)
                == msg.sender,
            "not NFT owner"
        );
        require(amount > 0, "zero amount");
        require(agent != address(0), "invalid agent");
        require(verifier != address(0), "invalid verifier");
        require(deadline > block.timestamp, "invalid deadline");

        reservable.reserveValue(tokenId, asset, amount);

        id = nextBondId++;
        bonds[id] = Bond(
            tokenId, asset, amount, agent, verifier, deadline, true
        );
    }

    function releaseByVerifier(uint256 id) external {
        Bond storage b = bonds[id];
        require(b.active, "inactive");
        require(msg.sender == b.verifier, "not verifier");
        _release(b);
    }

    function releaseAfterDeadline(uint256 id) external {
        Bond storage b = bonds[id];
        require(b.active, "inactive");
        require(block.timestamp >= b.deadline, "not expired");
        _release(b);
    }

    function _release(Bond storage b) internal {
        b.active = false;
        reservable.releaseValue(b.tokenId, b.asset, b.amount);
    }
}