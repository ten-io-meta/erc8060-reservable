// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../contracts/reference/ERC8060NativeETHReference.sol";
import "../contracts/CustodiedCollateralLoanPoC.sol";

contract RejectSaleNFTReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        revert("recipient rejects NFT");
    }
}

/// @notice A premium NFT sale must be value-conserving; the old ETH burn must
///         be impossible until the FULL agreed auction has run without buyer.
contract MarketFirstCollateralSaleFoundryTest is Test {
    ERC8060NativeETHReference internal nft;
    CustodiedCollateralLoanPoC internal loan;
    address internal constant BORROWER = address(0xA11CE);
    address internal constant LENDER = address(0xB0B);
    address internal constant BUYER = address(0xBEEF);
    address internal constant ARBITER = address(0xCAFE);
    address internal constant OUTSIDER = address(0xD00D);
    bytes32 internal constant TERMS = keccak256("borrower and lender consent to sale-first DUTCH at ETH floor");

    function setUp() public {
        vm.deal(BORROWER, 100 ether);
        vm.deal(LENDER, 100 ether);
        vm.deal(BUYER, 100 ether);
        vm.deal(OUTSIDER, 100 ether);
        vm.deal(ARBITER, 100 ether);
        nft = new ERC8060NativeETHReference();
        loan = new CustodiedCollateralLoanPoC(address(nft));
    }

    function _offer(uint256 startPrice) internal returns (uint256 loanId) {
        vm.startPrank(BORROWER);
        uint256 tokenId = nft.mint{value: 2 ether}();
        nft.approve(address(loan), tokenId);
        CustodiedCollateralLoanPoC.Offer memory o = CustodiedCollateralLoanPoC.Offer({
            tokenId: tokenId,
            lender: LENDER,
            arbiter: ARBITER,
            principal: 1 ether,
            payoff: 1.1 ether,
            fundingDeadline: uint64(block.timestamp + 1 days),
            term: uint64(1 days),
            grace: uint64(1 days),
            challenge: uint64(1 days),
            arbitrateFor: uint64(1 days),
            termsHash: TERMS,
            saleStartPrice: uint128(startPrice),
            saleDuration: uint64(1 hours)
        });
        loanId = loan.propose(o);
        vm.stopPrank();
        vm.prank(LENDER);
        loan.fund{value: 1 ether}(loanId, TERMS);
        assertEq(nft.ownerOf(tokenId), address(loan));
    }

    function _startAfterDefault(uint256 id) internal {
        vm.warp(block.timestamp + 3 days);
        vm.prank(OUTSIDER);
        loan.declareDefault(id);
        vm.expectRevert(bytes("challenge open"));
        loan.startSale(id);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(OUTSIDER);
        loan.startSale(id);
    }

    function testFuzz_BuyerPurchasesActualNFTAndDebtPlusSurplusAlwaysMatch(
        uint64 pricePremiumRaw, uint64 partialRaw, uint32 elapsedRaw
    ) public {
        uint256 premium = uint256(pricePremiumRaw) % 1 ether;
        uint256 startPrice = 3 ether + premium;
        uint256 id = _offer(startPrice);
        uint256 prepaid = uint256(partialRaw) % 1.1 ether;
        if (prepaid > 0) {
            vm.prank(BORROWER);
            loan.repay{value: prepaid}(id);
        }
        _startAfterDefault(id);
        uint256 elapsed = uint256(elapsedRaw) % 3600;
        vm.warp(block.timestamp + elapsed);
        uint256 quote = loan.currentSalePrice(id);
        assertGe(quote, 2 ether);
        assertLe(quote, startPrice);
        vm.expectRevert(bytes("auction still active"));
        loan.burnUnsold(id);
        vm.prank(BUYER);
        loan.buyCollateral{value: startPrice}(id, startPrice, BUYER);
        assertEq(nft.ownerOf(1), BUYER, "NFT market premium preserved");
        assertEq(nft.valueOf(1), 2 ether, "embedded ETH backing intact");
        assertEq(address(nft).balance, 2 ether);

        uint256 outstanding = 1.1 ether - prepaid;
        uint256 refund = startPrice - quote;
        assertEq(loan.credits(LENDER), 1.1 ether, "partial + sale lender award");
        assertEq(loan.credits(BORROWER), quote - outstanding, "borrower gets entire premium");
        assertEq(loan.credits(BUYER), refund, "buyer gets unused bid limit refunded");
        assertEq(loan.totalCredits(), prepaid + startPrice);
        assertEq(address(loan).balance, prepaid + startPrice, "all credits actually funded");
        assertTrue(loan.isCreditSolvent());

        vm.expectRevert(bytes("not sale open"));
        loan.burnUnsold(id);
        vm.expectRevert(bytes("not sale open"));
        vm.prank(OUTSIDER);
        loan.buyCollateral{value: startPrice}(id, startPrice, OUTSIDER);

        vm.prank(LENDER);
        loan.withdrawCredit(payable(LENDER));
        vm.prank(BORROWER);
        loan.withdrawCredit(payable(BORROWER));
        if (refund > 0) {
            vm.prank(BUYER);
            loan.withdrawCredit(payable(BUYER));
        }
        assertEq(loan.totalCredits(), 0, "no phantom claims after full withdrawal");
        assertEq(address(loan).balance, 0, "escrow fully cleared");
    }

    function testFuzz_UnsoldBurnMustWaitForAgreedDeadline(
        uint64 startPremiumRaw, uint64 partialRaw
    ) public {
        uint256 startPrice = 2 ether + (uint256(startPremiumRaw) % 1 ether);
        uint256 id = _offer(startPrice);
        uint256 prepaid = uint256(partialRaw) % 1.1 ether;
        if (prepaid > 0) {
            vm.prank(BORROWER);
            loan.repay{value: prepaid}(id);
        }
        _startAfterDefault(id);
        CustodiedCollateralLoanPoC.Loan memory l = loan.loanInfo(id);
        vm.expectRevert(bytes("auction still active"));
        vm.prank(LENDER);
        loan.burnUnsold(id);
        vm.warp(uint256(l.saleStartedAt) + l.saleDuration);
        vm.expectRevert(bytes("auction still active"));
        loan.burnUnsold(id);
        vm.warp(uint256(l.saleStartedAt) + l.saleDuration + 1);
        vm.prank(OUTSIDER);
        loan.burnUnsold(id);

        assertEq(nft.totalRedeemableValue(), 0, "burn occurs only at final fallback");
        assertEq(loan.credits(LENDER), 1.1 ether);
        assertEq(loan.credits(BORROWER), 2 ether - (1.1 ether - prepaid));
        assertEq(loan.totalCredits(), 2 ether + prepaid);
        assertEq(address(loan).balance, 2 ether + prepaid);
    }

    function test_SettlementAndLenderWaiverRemainPossibleDuringOpenSale() public {
        uint256 id = _offer(3 ether);
        _startAfterDefault(id);
        vm.prank(OUTSIDER);
        loan.settleAfterDefault{value: 1.1 ether}(id);
        vm.expectRevert(bytes("not sale open"));
        loan.burnUnsold(id);
        vm.expectRevert(bytes("not sale open"));
        vm.prank(BUYER);
        loan.buyCollateral{value: 3 ether}(id, 3 ether, BUYER);
        vm.prank(BORROWER);
        loan.claimCollateral(id, BORROWER);
        assertEq(nft.ownerOf(1), BORROWER);
        assertEq(loan.credits(LENDER), 1.1 ether);
    }

    function test_RejectingBuyerCannotFreezeLiquidationOrCreateFakeCredits() public {
        uint256 id = _offer(3 ether);
        _startAfterDefault(id);
        RejectSaleNFTReceiver rejector = new RejectSaleNFTReceiver();
        vm.expectRevert(bytes("recipient rejects NFT"));
        vm.prank(BUYER);
        loan.buyCollateral{value: 3 ether}(id, 3 ether, address(rejector));
        assertEq(nft.ownerOf(1), address(loan), "failed sale rolls back");
        assertEq(loan.totalCredits(), 0);
        assertEq(address(loan).balance, 0);
        vm.prank(BUYER);
        loan.buyCollateral{value: 3 ether}(id, 3 ether, BUYER);
        assertEq(nft.ownerOf(1), BUYER);
        assertEq(loan.totalCredits(), 3 ether);
    }

    function test_DisputedArbiterCanStartSaleButCannotSkipIt() public {
        uint256 id = _offer(3 ether);
        vm.warp(block.timestamp + 3 days);
        loan.declareDefault(id);
        vm.prank(BORROWER);
        loan.dispute(id);
        vm.expectRevert(bytes("challenge open"));
        vm.prank(ARBITER);
        loan.arbitrate(id, false);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(ARBITER);
        loan.arbitrate(id, false);
        vm.expectRevert(bytes("auction still active"));
        vm.prank(ARBITER);
        loan.burnUnsold(id);
        assertEq(nft.ownerOf(1), address(loan));
    }
}
