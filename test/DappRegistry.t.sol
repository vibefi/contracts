// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DappRegistry} from "../src/DappRegistry.sol";

contract DappRegistryTest is Test {
    address private governance = address(0xA11CE);
    address private securityCouncil = address(0xB0B);

    DappRegistry private registry;

    function setUp() public {
        registry = new DappRegistry(governance, securityCouncil);
    }

    function testPublishAndUpgrade() public {
        bytes memory cidV1 = hex"01701220"; // placeholder bytes for testing
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(
            cidV1,
            "Uniswap",
            "1.0.0",
            "Swap UI"
        );

        assertEq(dappId, 1);
        assertEq(versionId, 1);

        vm.prank(governance);
        uint256 newVersionId = registry.upgradeDapp(dappId, cidV1, "Uniswap", "1.1.0", "Swap UI v2");
        assertEq(newVersionId, 2);
    }

    function testSecurityCouncilPauseUnpause() public {
        bytes memory cidV1 = hex"01701220";
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(
            cidV1,
            "Vibe",
            "1.0.0",
            "Demo"
        );

        vm.prank(securityCouncil);
        registry.pauseDappVersion(dappId, versionId, "incident");

        vm.prank(securityCouncil);
        registry.unpauseDappVersion(dappId, versionId, "resolved");
    }
}
