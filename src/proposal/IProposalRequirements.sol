// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IProposalRequirements {
    function isEligible(address proposer, uint256 proposerVotes, uint256 totalSupply) external view returns (bool);

    function onProposalCreated(uint256 proposalId, address proposer) external;
}
