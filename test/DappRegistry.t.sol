// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DappRegistry} from "../src/DappRegistry.sol";
import {DeployVibeFi} from "../script/DeployVibeFi.s.sol";

contract DappRegistryTest is Test {
    address private securityCouncil = address(0xB0B);

    address private governance;
    DappRegistry private registry;
    DeployVibeFi private deployer;

    function setUp() public {
        deployer = new DeployVibeFi();
        DeployVibeFi.Params memory params = DeployVibeFi.Params({
            initialSupply: 1_000_000e18,
            votingDelay: 1,
            votingPeriod: 5,
            quorumFraction: 4,
            timelockDelay: 1,
            minProposalBps: 100
        });
        DeployVibeFi.Deployment memory dep = deployer.deploy(params, address(this), securityCouncil, false);
        dep.timelock.grantRole(dep.timelock.PROPOSER_ROLE(), address(dep.governor));
        dep.timelock.grantRole(dep.timelock.EXECUTOR_ROLE(), address(0));
        dep.timelock.grantRole(dep.timelock.CANCELLER_ROLE(), securityCouncil);
        dep.timelock.revokeRole(dep.timelock.DEFAULT_ADMIN_ROLE(), address(this));

        registry = dep.registry;
        governance = address(dep.timelock);
    }

    function testPublishAndUpgrade() public {
        bytes memory cidV1 = hex"01701220"; // placeholder bytes for testing
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(cidV1, "Uniswap", "1.0.0", "Swap UI");

        assertEq(dappId, 1);
        assertEq(versionId, 1);

        vm.prank(governance);
        uint256 newVersionId = registry.upgradeDapp(dappId, cidV1, "Uniswap", "1.1.0", "Swap UI v2");
        assertEq(newVersionId, 2);
    }

    function testSecurityCouncilPauseUnpause() public {
        bytes memory cidV1 = hex"01701220";
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(cidV1, "Vibe", "1.0.0", "Demo");

        vm.prank(securityCouncil);
        registry.pauseDappVersion(dappId, versionId, "incident");

        vm.prank(securityCouncil);
        registry.unpauseDappVersion(dappId, versionId, "resolved");
    }
}
