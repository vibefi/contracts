// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ConstraintsRegistry} from "../src/ConstraintsRegistry.sol";

contract ConstraintsRegistryTest is Test {
    bytes4 private constant ACCESS_CONTROL_UNAUTHORIZED_SELECTOR =
        bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    event ConstraintsUpdated(bytes32 indexed constraintsId, bytes rootCid, address updatedBy);

    address private governance = address(0xA11CE);
    address private user = address(0xB0B);

    ConstraintsRegistry private registry;

    function setUp() public {
        registry = new ConstraintsRegistry(governance);
    }

    function testGovernanceCanSetAndOverwriteConstraints() public {
        bytes32 constraintsId = keccak256("default");
        bytes memory cidV1 = hex"01701220";
        bytes memory cidV2 = hex"01701221";

        vm.expectEmit(true, true, true, true, address(registry));
        emit ConstraintsUpdated(constraintsId, cidV1, governance);
        vm.prank(governance);
        registry.setConstraints(constraintsId, cidV1);
        assertEq(registry.getConstraints(constraintsId), cidV1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ConstraintsUpdated(constraintsId, cidV2, governance);
        vm.prank(governance);
        registry.setConstraints(constraintsId, cidV2);
        assertEq(registry.getConstraints(constraintsId), cidV2);
    }

    function testSetConstraintsRevertsOnEmptyCid() public {
        vm.prank(governance);
        vm.expectRevert(ConstraintsRegistry.InvalidRootCid.selector);
        registry.setConstraints(keccak256("default"), bytes(""));
    }

    function testSetConstraintsRevertsForUnauthorizedCaller() public {
        vm.expectRevert(abi.encodeWithSelector(ACCESS_CONTROL_UNAUTHORIZED_SELECTOR, user, registry.GOVERNANCE_ROLE()));
        vm.prank(user);
        registry.setConstraints(keccak256("default"), hex"01");
    }
}
