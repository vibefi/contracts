// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProposalRequirements} from "./IProposalRequirements.sol";

contract MinimumDelegationRequirement is IProposalRequirements {
    uint256 public immutable minBps;

    error MinimumDelegationNotMet(uint256 proposerVotes, uint256 requiredVotes);

    constructor(uint256 minBps_) {
        minBps = minBps_;
    }

    function isEligible(
        address,
        uint256 proposerVotes,
        uint256 totalSupply
    ) external view override returns (bool) {
        if (totalSupply == 0) {
            return false;
        }
        uint256 requiredVotes = (totalSupply * minBps) / 10_000;
        if (proposerVotes < requiredVotes) {
            return false;
        }
        return true;
    }

    function onProposalCreated(uint256, address) external pure override {}
}
