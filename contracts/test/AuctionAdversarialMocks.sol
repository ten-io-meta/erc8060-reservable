// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IAuctionReentryTarget {
    function buyCollateral(uint256 id, uint256 maxPrice, address recipient) external payable;
}

/// @notice Adversarial callback during safeTransferFrom: attempts to buy the same
///         collateral again. The outer sale must succeed with reentry rejected.
contract AuctionReentrantReceiver is IERC721Receiver {
    address public immutable auction;
    uint256 public loanId;
    bool public attempted;
    bool public reentrySucceeded;
    constructor(address auction_) { auction = auction_; }
    function setLoanId(uint256 id) external { loanId = id; }
    function onERC721Received(address, address, uint256, bytes calldata)
        external override returns (bytes4)
    {
        attempted = true;
        (reentrySucceeded,) = auction.call(
            abi.encodeWithSelector(IAuctionReentryTarget.buyCollateral.selector, loanId, 0, address(this))
        );
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @notice Reject safe NFT delivery; sale and all ETH credits must roll back.
contract AuctionRejectingReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external pure override returns (bytes4)
    {
        revert("receiver rejects NFT");
    }
}

/// @notice Intentionally dishonest ERC721 with a fabricated ETH valueOf.
///         It has no ETH backing. This fixture demonstrates the explicit
///         trust assumption rather than pretending the loan validates it.
contract AuctionFakeValueNFT is ERC721 {
    uint256 public nextTokenId = 1;
    constructor() ERC721("Fake Value", "FAKE") {}
    function mint() external returns (uint256 id) {
        id = nextTokenId++;
        _safeMint(msg.sender, id);
    }
    receive() external payable {}
    function valueOf(uint256) external pure returns (uint256) {
        return 2 ether;
    }
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "not owner");
        _burn(tokenId); // Pays zero ETH, despite declaring 2 ether.
    }
}
