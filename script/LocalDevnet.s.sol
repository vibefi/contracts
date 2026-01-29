// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {DeployVibeFi} from "./DeployVibeFi.s.sol";

contract LocalDevnet is DeployVibeFi {
    function run() external override returns (Deployment memory dep) {
        uint256 devKey = vm.envUint("DEV_PRIVATE_KEY");
        uint256 voter1Key = vm.envUint("VOTER1_PRIVATE_KEY");
        uint256 voter2Key = vm.envUint("VOTER2_PRIVATE_KEY");
        uint256 council1Key = vm.envUint("SECURITY_COUNCIL_1_PRIVATE_KEY");
        uint256 council2Key = vm.envUint("SECURITY_COUNCIL_2_PRIVATE_KEY");

        address dev = vm.addr(devKey);
        address voter1 = vm.addr(voter1Key);
        address voter2 = vm.addr(voter2Key);
        address council1 = vm.addr(council1Key);
        address council2 = vm.addr(council2Key);

        Params memory params = Params({
            initialSupply: vm.envUint("INITIAL_SUPPLY"),
            votingDelay: uint48(vm.envUint("VOTING_DELAY")),
            votingPeriod: uint32(vm.envUint("VOTING_PERIOD")),
            quorumFraction: vm.envUint("QUORUM_FRACTION"),
            timelockDelay: vm.envUint("TIMELOCK_DELAY"),
            minProposalBps: vm.envUint("MIN_PROPOSAL_BPS")
        });

        uint256 voterAllocation = vm.envUint("VOTER_ALLOCATION");
        uint256 councilAllocation = vm.envUint("COUNCIL_ALLOCATION");

        vm.startBroadcast(devKey);
        dep = deploy(params, dev, council1, true);

        dep.token.transfer(voter1, voterAllocation);
        dep.token.transfer(voter2, voterAllocation);
        dep.token.transfer(council1, councilAllocation);
        dep.token.transfer(council2, councilAllocation);

        dep.token.delegate(dev);
        vm.stopBroadcast();

        vm.startBroadcast(voter1Key);
        dep.token.delegate(voter1);
        vm.stopBroadcast();

        vm.startBroadcast(voter2Key);
        dep.token.delegate(voter2);
        vm.stopBroadcast();

        vm.startBroadcast(council1Key);
        dep.token.delegate(council1);
        vm.stopBroadcast();

        vm.startBroadcast(council2Key);
        dep.token.delegate(council2);
        vm.stopBroadcast();

        string memory outputJson = vm.envOr("OUTPUT_JSON", string(""));
        if (bytes(outputJson).length != 0) {
            string memory json = "devnet";
            vm.serializeUint(json, "chainId", block.chainid);
            vm.serializeAddress(json, "vfiToken", address(dep.token));
            vm.serializeAddress(json, "vfiGovernor", address(dep.governor));
            vm.serializeAddress(json, "vfiTimelock", address(dep.timelock));
            vm.serializeAddress(json, "dappRegistry", address(dep.registry));
            vm.serializeAddress(json, "constraintsRegistry", address(dep.constraintsRegistry));
            vm.serializeAddress(json, "proposalRequirements", address(dep.requirements));

            vm.serializeAddress(json, "developer", dev);
            vm.serializeAddress(json, "voter1", voter1);
            vm.serializeAddress(json, "voter2", voter2);
            vm.serializeAddress(json, "securityCouncil1", council1);
            vm.serializeAddress(json, "securityCouncil2", council2);

            vm.serializeString(json, "developerPrivateKey", vm.toString(bytes32(devKey)));
            vm.serializeString(json, "voter1PrivateKey", vm.toString(bytes32(voter1Key)));
            vm.serializeString(json, "voter2PrivateKey", vm.toString(bytes32(voter2Key)));
            vm.serializeString(json, "securityCouncil1PrivateKey", vm.toString(bytes32(council1Key)));
            string memory jsonOut =
                vm.serializeString(json, "securityCouncil2PrivateKey", vm.toString(bytes32(council2Key)));

            vm.writeJson(jsonOut, outputJson);
        }

        console2.log("VibeFi local devnet deployed");
        console2.log("VfiToken:", address(dep.token));
        console2.log("VfiGovernor:", address(dep.governor));
        console2.log("VfiTimelock:", address(dep.timelock));
        console2.log("DappRegistry:", address(dep.registry));
        console2.log("ConstraintsRegistry:", address(dep.constraintsRegistry));
        console2.log("MinimumDelegationRequirement:", address(dep.requirements));
        console2.log("Deployer/Developer:", dev);
        console2.log("Voter1:", voter1);
        console2.log("Voter2:", voter2);
        console2.log("SecurityCouncil1:", council1);
        console2.log("SecurityCouncil2 (not assigned on-chain):", council2);
    }
}
