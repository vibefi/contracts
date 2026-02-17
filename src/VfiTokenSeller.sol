// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract VfiTokenSeller is Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidRate();
    error ZeroEthIn();
    error AmountTooSmall();
    error SlippageExceeded(uint256 minTokensOut, uint256 actualTokensOut);
    error InsufficientTokenInventory(uint256 requested, uint256 available);
    error InvalidAmount();
    error InsufficientEthBalance(uint256 requested, uint256 available);
    error EthTransferFailed();

    event TokensPurchased(address indexed buyer, address indexed recipient, uint256 ethIn, uint256 tokensOut);
    event TokensPerEthUpdated(uint256 oldRate, uint256 newRate);
    event EthWithdrawn(address indexed to, uint256 amount);
    event UnsoldTokensWithdrawn(address indexed to, uint256 amount);

    IERC20 public immutable token;

    // Token units (18 decimals) sold per 1 ether.
    uint256 public tokensPerEth;

    constructor(IERC20 token_, uint256 tokensPerEth_, address owner_) Ownable(owner_) {
        if (address(token_) == address(0) || owner_ == address(0)) revert ZeroAddress();
        if (tokensPerEth_ == 0) revert InvalidRate();

        token = token_;
        tokensPerEth = tokensPerEth_;
    }

    receive() external payable {
        _buy(msg.sender, 0);
    }

    function setTokensPerEth(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidRate();

        uint256 oldRate = tokensPerEth;
        tokensPerEth = newRate;
        emit TokensPerEthUpdated(oldRate, newRate);
    }

    function buy(address recipient, uint256 minTokensOut) external payable returns (uint256 tokensOut) {
        if (recipient == address(0)) revert ZeroAddress();
        tokensOut = _buy(recipient, minTokensOut);
    }

    function quoteTokenAmount(uint256 ethAmountWei) public view returns (uint256) {
        return Math.mulDiv(ethAmountWei, tokensPerEth, 1 ether);
    }

    function tokensAvailable() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function withdrawEth(address payable to, uint256 amountWei) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amountWei == 0) revert InvalidAmount();

        uint256 balance = address(this).balance;
        if (amountWei > balance) revert InsufficientEthBalance(amountWei, balance);

        (bool ok,) = to.call{value: amountWei}("");
        if (!ok) revert EthTransferFailed();

        emit EthWithdrawn(to, amountWei);
    }

    function withdrawUnsoldTokens(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 available = token.balanceOf(address(this));
        if (amount > available) revert InsufficientTokenInventory(amount, available);

        token.safeTransfer(to, amount);
        emit UnsoldTokensWithdrawn(to, amount);
    }

    function _buy(address recipient, uint256 minTokensOut) internal returns (uint256 tokensOut) {
        if (msg.value == 0) revert ZeroEthIn();

        tokensOut = quoteTokenAmount(msg.value);
        if (tokensOut == 0) revert AmountTooSmall();
        if (tokensOut < minTokensOut) revert SlippageExceeded(minTokensOut, tokensOut);

        uint256 available = token.balanceOf(address(this));
        if (tokensOut > available) revert InsufficientTokenInventory(tokensOut, available);

        token.safeTransfer(recipient, tokensOut);
        emit TokensPurchased(msg.sender, recipient, msg.value, tokensOut);
    }
}
