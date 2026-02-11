// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VfiToken} from "../src/VfiToken.sol";
import {VfiGovernor} from "../src/VfiGovernor.sol";
import {VfiTimelock} from "../src/VfiTimelock.sol";
import {DappRegistry} from "../src/DappRegistry.sol";
import {ConstraintsRegistry} from "../src/ConstraintsRegistry.sol";
import {MinimumDelegationRequirement} from "../src/proposal/MinimumDelegationRequirement.sol";

contract DeployVibeFi is Script {
    struct Params {
        uint256 initialSupply;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 quorumFraction;
        uint256 timelockDelay;
        uint256 minProposalBps;
    }

    struct Deployment {
        VfiToken token;
        VfiGovernor governor;
        VfiTimelock timelock;
        DappRegistry registry;
        ConstraintsRegistry constraintsRegistry;
        MinimumDelegationRequirement requirements;
    }

    function writeDeploymentJson(Deployment memory dep, address deployer, address securityCouncil) internal {
        string memory outputJson = vm.envOr("OUTPUT_JSON", string(""));
        if (bytes(outputJson).length == 0) {
            return;
        }

        string memory json = "deployment";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeUint(json, "deployBlock", block.number);
        vm.serializeAddress(json, "vfiToken", address(dep.token));
        vm.serializeAddress(json, "vfiGovernor", address(dep.governor));
        vm.serializeAddress(json, "vfiTimelock", address(dep.timelock));
        vm.serializeAddress(json, "dappRegistry", address(dep.registry));
        vm.serializeAddress(json, "constraintsRegistry", address(dep.constraintsRegistry));
        vm.serializeAddress(json, "proposalRequirements", address(dep.requirements));

        vm.serializeAddress(json, "deployer", deployer);
        vm.serializeAddress(json, "securityCouncil", securityCouncil);

        // Keep a superset compatible with the CLI devnet JSON loader.
        vm.serializeAddress(json, "developer", deployer);
        vm.serializeString(json, "developerPrivateKey", "");
        vm.serializeAddress(json, "voter1", address(0));
        vm.serializeString(json, "voter1PrivateKey", "");
        vm.serializeAddress(json, "voter2", address(0));
        vm.serializeString(json, "voter2PrivateKey", "");
        vm.serializeAddress(json, "securityCouncil1", securityCouncil);
        vm.serializeString(json, "securityCouncil1PrivateKey", "");
        vm.serializeAddress(json, "securityCouncil2", address(0));
        vm.serializeString(json, "securityCouncil2PrivateKey", "");

        vm.serializeBool(json, "localNetwork", false);
        string memory jsonOut = vm.serializeString(json, "rpcUrl", vm.envOr("RPC_URL", string("")));
        vm.writeJson(jsonOut, outputJson);
    }

    function deploy(Params memory params, address initialHolder, address securityCouncil, bool configureTimelockRoles)
        public
        returns (Deployment memory dep)
    {
        dep.token = new VfiToken("VibeFi", "VFI", params.initialSupply, initialHolder);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        dep.timelock = new VfiTimelock(params.timelockDelay, proposers, executors, initialHolder);

        dep.requirements = new MinimumDelegationRequirement(params.minProposalBps);
        dep.governor = new VfiGovernor(
            dep.token,
            dep.timelock,
            params.votingDelay,
            params.votingPeriod,
            0,
            params.quorumFraction,
            dep.requirements,
            securityCouncil
        );

        if (configureTimelockRoles) {
            dep.timelock.grantRole(dep.timelock.PROPOSER_ROLE(), address(dep.governor));
            dep.timelock.grantRole(dep.timelock.EXECUTOR_ROLE(), address(0));
        }

        dep.registry = new DappRegistry(address(dep.timelock), securityCouncil);
        dep.constraintsRegistry = new ConstraintsRegistry(address(dep.timelock));
    }

    function run() external virtual returns (Deployment memory dep) {
        address securityCouncil = vm.envAddress("SECURITY_COUNCIL");

        Params memory params = Params({
            initialSupply: vm.envUint("INITIAL_SUPPLY"),
            votingDelay: uint48(vm.envUint("VOTING_DELAY")),
            votingPeriod: uint32(vm.envUint("VOTING_PERIOD")),
            quorumFraction: vm.envUint("QUORUM_FRACTION"),
            timelockDelay: vm.envUint("TIMELOCK_DELAY"),
            minProposalBps: vm.envUint("MIN_PROPOSAL_BPS")
        });

        vm.startBroadcast();
        address deployer = tx.origin;
        dep = deploy(params, deployer, securityCouncil, true);
        vm.stopBroadcast();

        writeDeploymentJson(dep, deployer, securityCouncil);
    }
}
