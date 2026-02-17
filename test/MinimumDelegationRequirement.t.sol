// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinimumDelegationRequirement} from "../src/proposal/MinimumDelegationRequirement.sol";

contract MinimumDelegationRequirementTest is Test {
    MinimumDelegationRequirement private requirement;

    function setUp() public {
        requirement = new MinimumDelegationRequirement(100); // 1%
    }

    function testIsEligibleFalseWhenTotalSupplyIsZero() public view {
        assertFalse(requirement.isEligible(address(1), 1, 0));
    }

    function testIsEligibleFalseBelowRequiredThreshold() public view {
        assertFalse(requirement.isEligible(address(1), 99, 10_000));
    }

    function testIsEligibleTrueAtExactThreshold() public view {
        assertTrue(requirement.isEligible(address(1), 100, 10_000));
    }

    function testIsEligibleTrueAboveThreshold() public view {
        assertTrue(requirement.isEligible(address(1), 101, 10_000));
    }

    function testOnProposalCreatedIsNoop() public view {
        requirement.onProposalCreated(1, address(1));
    }
}
