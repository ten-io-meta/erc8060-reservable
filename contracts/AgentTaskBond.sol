// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC8060Reservable.sol";

/**
 * @title AgentTaskBond
 * @notice Minimal demo showing how IERC8060Reservable can support agent task bonds.
 * @dev This contract does not define reputation, validation, or settlement rules.
 *      It only demonstrates that value can be committed for an agent task
 *      without transferring ownership or custody of the NFT.
 */
interface ITaskBondOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice ACCOUNTING-ONLY DEMO; no task verification or agent payout.
contract AgentTaskBond {
    IERC8060Reservable public immutable reservable;

    struct Bond {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address agent;
        bytes32 taskHash;
        bool active;
        bool settled;
    }

    uint256 public nextBondId;
    mapping(uint256 => Bond) public bonds;
    mapping(uint256 => address) public creators;

    event TaskBondCreated(
        uint256 indexed bondId,
        uint256 indexed tokenId,
        address indexed agent,
        address asset,
        uint256 amount,
        bytes32 taskHash
    );

    event TaskBondReleased(uint256 indexed bondId);
    event TaskBondSettled(uint256 indexed bondId);

    constructor(address reservable_) {
        require(reservable_ != address(0), "invalid reservable");
        reservable = IERC8060Reservable(reservable_);
    }

    function createTaskBond(
        uint256 tokenId,
        address asset,
        uint256 amount,
        address agent,
        bytes32 taskHash
    ) external returns (uint256 bondId) {
        require(ITaskBondOwner(address(reservable)).ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(agent != address(0), "invalid agent");
        require(amount > 0, "amount is zero");
        require(taskHash != bytes32(0), "empty task hash");

        reservable.reserveValue(tokenId, asset, amount);

        bondId = nextBondId++;

        creators[bondId] = msg.sender;
        bonds[bondId] = Bond({
            tokenId: tokenId,
            asset: asset,
            amount: amount,
            agent: agent,
            taskHash: taskHash,
            active: true,
            settled: false
        });

        emit TaskBondCreated(
            bondId,
            tokenId,
            agent,
            asset,
            amount,
            taskHash
        );
    }

    function releaseTaskBond(uint256 bondId) external {
        Bond storage b = bonds[bondId];

        require(b.active, "bond not active");
        require(!b.settled, "bond already settled");
        require(msg.sender == creators[bondId], "not bond creator");

        b.active = false;

        reservable.releaseValue(b.tokenId, b.asset, b.amount);

        emit TaskBondReleased(bondId);
    }

    /// @notice No settlement without a verified task result and payment logic.
    function settleTaskBond(uint256) external pure {
        revert("settlement not implemented");
    }
}
