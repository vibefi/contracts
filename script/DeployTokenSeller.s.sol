// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {VfiTokenSeller} from "../src/VfiTokenSeller.sol";

contract DeployTokenSeller is Script {
    function run() external returns (VfiTokenSeller seller) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address tokenAddress = vm.envAddress("VFI_TOKEN_ADDRESS");
        uint256 rate = vm.envUint("TOKENS_PER_ETH");
        address sellerOwner = vm.envOr("SELLER_OWNER", deployer);

        vm.startBroadcast(deployerKey);
        seller = new VfiTokenSeller(IERC20(tokenAddress), rate, sellerOwner);
        vm.stopBroadcast();

        console2.log("VfiTokenSeller:", address(seller));
        console2.log("Token:", tokenAddress);
        console2.log("Owner:", sellerOwner);
        console2.log("Tokens per ETH:", rate);
    }
}
