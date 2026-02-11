// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {DeployVibeFi} from "./DeployVibeFi.s.sol";

contract DeploySepolia is DeployVibeFi {
    function run() external override returns (Deployment memory dep) {
        string memory mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        uint256 deployerKey = vm.deriveKey(mnemonic, 0);
        address deployer = vm.addr(deployerKey);

        Params memory params = Params({
            initialSupply: 1_000_000e18,
            votingDelay: 1,
            votingPeriod: 50,
            quorumFraction: 1,
            timelockDelay: 60,
            minProposalBps: 100
        });

        vm.startBroadcast(deployerKey);
        dep = deploy(params, deployer, deployer, true);
        dep.token.delegate(deployer);
        vm.stopBroadcast();

        string memory outputJson = vm.envOr("OUTPUT_JSON", string(""));
        if (bytes(outputJson).length != 0) {
            string memory json = "sepolia";
            vm.serializeUint(json, "chainId", block.chainid);
            vm.serializeUint(json, "deployBlock", block.number);
            vm.serializeAddress(json, "vfiToken", address(dep.token));
            vm.serializeAddress(json, "vfiGovernor", address(dep.governor));
        vm.serializeAddress(json, "vfiTimelock", address(dep.timelock));
            vm.serializeAddress(json, "dappRegistry", address(dep.registry));
            vm.serializeAddress(json, "constraintsRegistry", address(dep.constraintsRegistry));
            vm.serializeAddress(json, "proposalRequirements", address(dep.requirements));
            vm.serializeAddress(json, "deployer", deployer);
            vm.serializeBool(json, "localNetwork", false);
            string memory jsonOut =
                vm.serializeString(json, "rpcUrl", vm.envOr("SEPOLIA_RPC_URL", string("")));

            vm.writeJson(jsonOut, outputJson);
        }

        console2.log("VibeFi deployed to Sepolia");
        console2.log("VfiToken:", address(dep.token));
        console2.log("VfiGovernor:", address(dep.governor));
        console2.log("VfiTimelock:", address(dep.timelock));
        console2.log("DappRegistry:", address(dep.registry));
        console2.log("ConstraintsRegistry:", address(dep.constraintsRegistry));
        console2.log("MinimumDelegationRequirement:", address(dep.requirements));
        console2.log("Deployer:", deployer);
    }
}
