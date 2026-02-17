// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {VfiTokenSeller} from "../src/VfiTokenSeller.sol";

contract DeployTokenSeller is Script {
    using SafeERC20 for IERC20;

    uint256 internal constant TOKENS_PER_ETH = 10e18;
    uint256 internal constant INITIAL_SELLER_INVENTORY = 10_000e18;

    function run() external returns (VfiTokenSeller seller) {
        string memory mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        uint256 deployerKey = vm.deriveKey(mnemonic, 0);
        address deployer = vm.addr(deployerKey);

        address tokenAddress = vm.envAddress("VFI_TOKEN_ADDRESS");
        address sellerOwner = vm.envOr("SELLER_OWNER", deployer);
        IERC20 token = IERC20(tokenAddress);

        vm.startBroadcast(deployerKey);
        seller = new VfiTokenSeller(token, TOKENS_PER_ETH, sellerOwner);
        token.safeTransfer(address(seller), INITIAL_SELLER_INVENTORY);
        vm.stopBroadcast();

        console2.log("VfiTokenSeller:", address(seller));
        console2.log("Token:", tokenAddress);
        console2.log("Owner:", sellerOwner);
        console2.log("Tokens per ETH:", TOKENS_PER_ETH);
        console2.log("Initial seller inventory:", INITIAL_SELLER_INVENTORY);
    }
}
