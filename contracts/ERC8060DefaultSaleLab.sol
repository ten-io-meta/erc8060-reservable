// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC721ValueLab {
    function valueOf(uint256 tokenId) external view returns (uint256);
    function burn(uint256 tokenId) external;
}

// ERC-721 con ETH real depositado. SOLO LABORATORIO.
contract ERC8060BackedNFTLab is ERC721, ReentrancyGuard, IERC721ValueLab {
    uint256 private _nextId = 1;
    mapping(uint256 => uint256) private _backing;

    constructor() ERC721("ERC8060 Lab NFT", "LAB8060") {}

    function mint() external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value == 1 ether, "mint exactly 1 ETH");
        tokenId = _nextId++;
        _backing[tokenId] = msg.value;
        _safeMint(msg.sender, tokenId);
    }

    function valueOf(uint256 tokenId)
        external view override returns (uint256)
    {
        require(_exists(tokenId), "nonexistent token");
        return _backing[tokenId];
    }

    function burn(uint256 tokenId) external override nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "owner only");
        uint256 amount = _backing[tokenId];
        delete _backing[tokenId];
        _burn(tokenId);
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "redemption failed");
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721) returns (bool)
    {
        return interfaceId == type(IERC721ValueLab).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

// Liquidacion mediante venta voluntariamente pactada del NFT.
// El ETH que respalda el NFT permanece intacto.
// Esta alternativa NO utiliza IERC8060Reservable.
contract ERC8060DefaultSaleLab is IERC721Receiver, ReentrancyGuard {
    enum Status {
        None,
        Unfunded,
        Funded,
        Repaid,
        Cancelled,
        Liquidated
    }

    struct Loan {
        uint256 tokenId;
        uint256 principal;
        uint256 salePrice;
        address borrower;
        address lender;
        uint64 fundingExpiry;
        uint64 loanDuration;
        uint64 repayDeadline;
        Status status;
    }

    IERC721 public immutable nft;
    IERC721ValueLab public immutable valueToken;

    uint256 public nextLoanId;
    mapping(uint256 => Loan) public loans;
    mapping(uint256 => bool) public tokenOnLoan;
    mapping(address => uint256) public credits;

    uint256 private _expectedToken;
    address private _expectedFrom;

    event LoanOpened(
        uint256 indexed loanId,
        uint256 indexed tokenId,
        address borrower,
        address lender
    );

    event LoanFunded(
        uint256 indexed loanId,
        uint64 repayDeadline
    );

    event LoanRepaid(uint256 indexed loanId);
    event LoanCancelled(uint256 indexed loanId);

    event LoanLiquidated(
        uint256 indexed loanId,
        address indexed buyer,
        uint256 salePrice
    );

    event CreditWithdrawn(address indexed recipient, uint256 amount);

    constructor(address nft_) {
        require(nft_ != address(0), "invalid NFT");
        require(
            IERC165(nft_).supportsInterface(type(IERC721).interfaceId),
            "not ERC721"
        );
        require(
            IERC165(nft_).supportsInterface(type(IERC721ValueLab).interfaceId),
            "not strict ERC8060"
        );
        nft = IERC721(nft_);
        valueToken = IERC721ValueLab(nft_);
    }

    function openLoan(
        uint256 tokenId,
        address lender,
        uint256 principal,
        uint256 salePrice,
        uint64 fundingExpiry,
        uint64 loanDuration
    ) external nonReentrant returns (uint256 id) {
        require(nft.ownerOf(tokenId) == msg.sender, "not NFT owner");
        require(!tokenOnLoan[tokenId], "already pledged");
        require(
            lender != address(0) && lender != msg.sender,
            "invalid lender"
        );
        require(principal > 0 && salePrice >= principal, "invalid terms");
        require(
            salePrice >= valueToken.valueOf(tokenId),
            "sale below ETH backing"
        );
        require(fundingExpiry > block.timestamp, "invalid funding expiry");
        require(
            loanDuration > 0 && loanDuration <= 365 days,
            "invalid loan duration"
        );

        tokenOnLoan[tokenId] = true;
        _expectedToken = tokenId;
        _expectedFrom = msg.sender;

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        _expectedFrom = address(0);

        id = nextLoanId++;
        loans[id] = Loan(
            tokenId,
            principal,
            salePrice,
            msg.sender,
            lender,
            fundingExpiry,
            loanDuration,
            0,
            Status.Unfunded
        );

        emit LoanOpened(id, tokenId, msg.sender, lender);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external view override returns (bytes4) {
        require(msg.sender == address(nft), "foreign NFT");
        require(
            operator == address(this)
                && from == _expectedFrom
                && tokenId == _expectedToken,
            "unsolicited NFT"
        );
        return IERC721Receiver.onERC721Received.selector;
    }

    function fundLoan(uint256 id) external payable nonReentrant {
        Loan storage l = loans[id];

        require(l.status == Status.Unfunded, "not fundable");
        require(msg.sender == l.lender, "not lender");
        require(block.timestamp < l.fundingExpiry, "funding expired");
        require(msg.value == l.principal, "wrong funding");
        require(
            nft.ownerOf(l.tokenId) == address(this),
            "NFT missing"
        );
        require(
            l.salePrice >= valueToken.valueOf(l.tokenId),
            "backing exceeds price"
        );

        l.status = Status.Funded;
        l.repayDeadline = uint64(
            block.timestamp + uint256(l.loanDuration)
        );

        (bool ok, ) = payable(l.borrower).call{value: msg.value}("");
        require(ok, "funding transfer failed");

        emit LoanFunded(id, l.repayDeadline);
    }

    function repayLoan(uint256 id) external payable nonReentrant {
        Loan storage l = loans[id];

        require(l.status == Status.Funded, "not repayable");
        require(msg.value == l.principal, "full principal required");

        l.status = Status.Repaid;
        tokenOnLoan[l.tokenId] = false;
        credits[l.lender] += msg.value;

        nft.safeTransferFrom(address(this), l.borrower, l.tokenId);

        emit LoanRepaid(id);
    }

    function cancelUnfunded(uint256 id) external nonReentrant {
        Loan storage l = loans[id];

        require(l.status == Status.Unfunded, "already funded");
        require(
            msg.sender == l.borrower
                || block.timestamp >= l.fundingExpiry,
            "not authorized"
        );

        l.status = Status.Cancelled;
        tokenOnLoan[l.tokenId] = false;

        nft.safeTransferFrom(address(this), l.borrower, l.tokenId);

        emit LoanCancelled(id);
    }

    function buyDefaultedNFT(
        uint256 id,
        uint256 buyerMinBacking
    ) external payable nonReentrant {
        Loan storage l = loans[id];

        require(l.status == Status.Funded, "not funded");
        require(block.timestamp > l.repayDeadline, "not in default");
        require(msg.value == l.salePrice, "wrong sale price");

        uint256 currentBacking = valueToken.valueOf(l.tokenId);

        require(
            currentBacking >= buyerMinBacking,
            "below buyer minimum"
        );
        require(l.salePrice >= currentBacking, "price below backing");

        l.status = Status.Liquidated;
        tokenOnLoan[l.tokenId] = false;

        credits[l.lender] += l.principal;
        credits[l.borrower] += msg.value - l.principal;

        nft.safeTransferFrom(address(this), msg.sender, l.tokenId);

        emit LoanLiquidated(id, msg.sender, msg.value);
    }

    function withdrawCredit() external nonReentrant {
        uint256 amount = credits[msg.sender];

        require(amount > 0, "no credit");
        credits[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");

        emit CreditWithdrawn(msg.sender, amount);
    }
}