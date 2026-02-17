// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DappRegistry} from "../src/DappRegistry.sol";

contract DappRegistryTest is Test {
    bytes4 private constant ACCESS_CONTROL_UNAUTHORIZED_SELECTOR =
        bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    event DappPublished(uint256 indexed dappId, uint256 indexed versionId, bytes rootCid, address proposer);
    event DappUpgraded(
        uint256 indexed dappId,
        uint256 indexed fromVersionId,
        uint256 indexed toVersionId,
        bytes rootCid,
        address proposer
    );

    address private governance = address(0xA11CE);
    address private securityCouncil = address(0xB0B);
    address private eve = address(0xE11E);

    DappRegistry private registry;

    function setUp() public {
        registry = new DappRegistry(governance, securityCouncil);
    }

    function testPublishAndUpgrade() public {
        bytes memory cidV1 = hex"01701220"; // placeholder bytes for testing
        bytes memory cidV2 = hex"01701221";

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappPublished(1, 1, cidV1, governance);
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(cidV1, "Uniswap", "1.0.0", "Swap UI");

        assertEq(dappId, 1);
        assertEq(versionId, 1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappUpgraded(1, 1, 2, cidV2, governance);
        vm.prank(governance);
        uint256 newVersionId = registry.upgradeDapp(dappId, cidV2, "Uniswap", "1.1.0", "Swap UI v2");
        assertEq(newVersionId, 2);
        assertEq(registry.latestVersionId(dappId), 2);

        (bytes memory rootCid, DappRegistry.VersionStatus status, address proposer, uint48 createdAt) =
            registry.getDappVersion(dappId, newVersionId);
        assertEq(rootCid, cidV2);
        assertEq(uint256(status), uint256(DappRegistry.VersionStatus.Published));
        assertEq(proposer, governance);
        assertGt(createdAt, 0);
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

    function testOnlyGovernanceCanPublish() public {
        vm.expectRevert(
            abi.encodeWithSelector(ACCESS_CONTROL_UNAUTHORIZED_SELECTOR, eve, registry.GOVERNANCE_ROLE())
        );
        vm.prank(eve);
        registry.publishDapp(hex"01", "Name", "1.0.0", "Summary");
    }

    function testPublishRevertsOnEmptyCid() public {
        vm.prank(governance);
        vm.expectRevert(DappRegistry.InvalidRootCid.selector);
        registry.publishDapp(bytes(""), "Name", "1.0.0", "Summary");
    }

    function testUpgradeRevertsForUnknownDapp() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(DappRegistry.DappVersionNotFound.selector, 77, 0));
        registry.upgradeDapp(77, hex"01", "Name", "1.0.1", "Summary");
    }

    function testGetDappVersionRevertsForUnknownVersion() public {
        vm.expectRevert(abi.encodeWithSelector(DappRegistry.DappVersionNotFound.selector, 1, 1));
        registry.getDappVersion(1, 1);
    }

    function testUnpauseRevertsUnlessVersionIsPaused() public {
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(hex"01", "Name", "1.0.0", "Summary");

        vm.prank(securityCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(
                DappRegistry.InvalidStatusTransition.selector,
                DappRegistry.VersionStatus.Published,
                DappRegistry.VersionStatus.Published
            )
        );
        registry.unpauseDappVersion(dappId, versionId, "not paused");
    }

    function testPauseRevertsOnceVersionIsDeprecated() public {
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(hex"01", "Name", "1.0.0", "Summary");

        vm.prank(securityCouncil);
        registry.deprecateDappVersion(dappId, versionId, "superseded");

        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                DappRegistry.InvalidStatusTransition.selector,
                DappRegistry.VersionStatus.Deprecated,
                DappRegistry.VersionStatus.Paused
            )
        );
        registry.pauseDappVersion(dappId, versionId, "incident");
    }

    function testDeprecateRevertsWhenAlreadyDeprecated() public {
        vm.prank(governance);
        (uint256 dappId, uint256 versionId) = registry.publishDapp(hex"01", "Name", "1.0.0", "Summary");

        vm.prank(governance);
        registry.deprecateDappVersion(dappId, versionId, "superseded");

        vm.prank(securityCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(
                DappRegistry.InvalidStatusTransition.selector,
                DappRegistry.VersionStatus.Deprecated,
                DappRegistry.VersionStatus.Deprecated
            )
        );
        registry.deprecateDappVersion(dappId, versionId, "again");
    }
}
