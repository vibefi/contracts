// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {VfiToken} from "../src/VfiToken.sol";
import {VfiTokenSeller} from "../src/VfiTokenSeller.sol";

contract VfiTokenSellerTest is Test {
    VfiToken private token;
    VfiTokenSeller private seller;

    address private constant BUYER = address(0xBEEF);
    address private constant RECIPIENT = address(0xCAFE);
    address private constant NON_OWNER = address(0xBAD);
    uint256 private constant TOKENS_PER_ETH = 1_000e18;

    function setUp() public {
        token = new VfiToken("VibeFi", "VFI", 2_000_000e18, address(this));
        seller = new VfiTokenSeller(IERC20(address(token)), TOKENS_PER_ETH, address(this));

        assertTrue(token.transfer(address(seller), 1_000_000e18));
        vm.deal(BUYER, 10 ether);
    }

    function testBuyTransfersTokensAndCollectsEth() public {
        uint256 ethIn = 0.25 ether;
        uint256 expectedTokens = seller.quoteTokenAmount(ethIn);

        vm.prank(BUYER);
        uint256 tokensOut = seller.buy{value: ethIn}(BUYER, expectedTokens);

        assertEq(tokensOut, expectedTokens);
        assertEq(token.balanceOf(BUYER), expectedTokens);
        assertEq(address(seller).balance, ethIn);
    }

    function testReceiveBuysForSender() public {
        uint256 ethIn = 0.01 ether;
        uint256 expectedTokens = seller.quoteTokenAmount(ethIn);

        vm.prank(BUYER);
        (bool ok,) = address(seller).call{value: ethIn}("");

        assertTrue(ok);
        assertEq(token.balanceOf(BUYER), expectedTokens);
    }

    function testBuyRevertsOnSlippage() public {
        uint256 ethIn = 0.05 ether;
        uint256 expectedTokens = seller.quoteTokenAmount(ethIn);

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(VfiTokenSeller.SlippageExceeded.selector, expectedTokens + 1, expectedTokens)
        );
        seller.buy{value: ethIn}(BUYER, expectedTokens + 1);
    }

    function testBuyRevertsWhenInventoryIsTooLow() public {
        uint256 available = token.balanceOf(address(seller));
        seller.withdrawUnsoldTokens(address(this), available - 1e18);

        uint256 ethIn = 0.01 ether;
        uint256 expectedTokens = seller.quoteTokenAmount(ethIn);

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(VfiTokenSeller.InsufficientTokenInventory.selector, expectedTokens, 1e18)
        );
        seller.buy{value: ethIn}(BUYER, 0);
    }

    function testBuyRevertsOnZeroEthIn() public {
        vm.prank(BUYER);
        vm.expectRevert(VfiTokenSeller.ZeroEthIn.selector);
        seller.buy{value: 0}(BUYER, 0);
    }

    function testBuyRevertsOnTooSmallAmount() public {
        VfiTokenSeller tinyRateSeller = new VfiTokenSeller(IERC20(address(token)), 1, address(this));
        assertTrue(token.transfer(address(tinyRateSeller), 10e18));

        vm.prank(BUYER);
        vm.expectRevert(VfiTokenSeller.AmountTooSmall.selector);
        tinyRateSeller.buy{value: 1}(BUYER, 0);
    }

    function testOnlyOwnerCanSetRate() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        seller.setTokensPerEth(2_000e18);
    }

    function testSetRateRevertsOnZeroRate() public {
        vm.expectRevert(VfiTokenSeller.InvalidRate.selector);
        seller.setTokensPerEth(0);
    }

    function testWithdrawEthTransfersEthToRecipient() public {
        vm.prank(BUYER);
        seller.buy{value: 1 ether}(BUYER, 0);

        uint256 recipientBalanceBefore = RECIPIENT.balance;
        seller.withdrawEth(payable(RECIPIENT), 0.4 ether);

        assertEq(RECIPIENT.balance, recipientBalanceBefore + 0.4 ether);
        assertEq(address(seller).balance, 0.6 ether);
    }

    function testWithdrawUnsoldTokensTransfersTokens() public {
        uint256 ownerBalanceBefore = token.balanceOf(address(this));
        seller.withdrawUnsoldTokens(address(this), 100e18);

        assertEq(token.balanceOf(address(this)), ownerBalanceBefore + 100e18);
    }

    function testConstructorValidation() public {
        vm.expectRevert(VfiTokenSeller.ZeroAddress.selector);
        new VfiTokenSeller(IERC20(address(0)), TOKENS_PER_ETH, address(this));

        vm.expectRevert(VfiTokenSeller.InvalidRate.selector);
        new VfiTokenSeller(IERC20(address(token)), 0, address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new VfiTokenSeller(IERC20(address(token)), TOKENS_PER_ETH, address(0));
    }
}
