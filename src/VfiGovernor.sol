// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "openzeppelin-contracts/governance/Governor.sol";
import {GovernorSettings} from "openzeppelin-contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "openzeppelin-contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "openzeppelin-contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "openzeppelin-contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "openzeppelin-contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {TimelockController} from "openzeppelin-contracts/governance/TimelockController.sol";

import {IProposalRequirements} from "./proposal/IProposalRequirements.sol";

contract VfiGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    IProposalRequirements public proposalRequirements;
    address public securityCouncil;

    event ProposalRequirementsUpdated(address indexed requirements);
    event SecurityCouncilUpdated(address indexed previousCouncil, address indexed newCouncil);
    event SecurityCouncilVeto(uint256 indexed proposalId, address indexed vetoedBy);

    error ProposalRequirementsNotMet(address proposer);
    error SecurityCouncilOnly(address caller);

    constructor(
        IVotes token,
        TimelockController timelock,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 quorumFraction,
        IProposalRequirements requirements,
        address securityCouncil_
    )
        Governor("VibeFi Governor")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(quorumFraction)
        GovernorTimelockControl(timelock)
    {
        proposalRequirements = requirements;
        securityCouncil = securityCouncil_;
        emit ProposalRequirementsUpdated(address(requirements));
        emit SecurityCouncilUpdated(address(0), securityCouncil_);
    }

    function setProposalRequirements(IProposalRequirements requirements) external onlyGovernance {
        proposalRequirements = requirements;
        emit ProposalRequirementsUpdated(address(requirements));
    }

    function setSecurityCouncil(address newCouncil) external onlyGovernance {
        address previous = securityCouncil;
        securityCouncil = newCouncil;
        emit SecurityCouncilUpdated(previous, newCouncil);
    }

    function vetoProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256 proposalId) {
        if (_msgSender() != securityCouncil) {
            revert SecurityCouncilOnly(_msgSender());
        }
        proposalId = _cancel(targets, values, calldatas, descriptionHash);
        emit SecurityCouncilVeto(proposalId, _msgSender());
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        if (address(proposalRequirements) != address(0)) {
            uint256 timepoint = clock() - 1;
            uint256 proposerVotes = getVotes(_msgSender(), timepoint);
            uint256 totalSupply = token().getPastTotalSupply(timepoint);
            if (!proposalRequirements.isEligible(_msgSender(), proposerVotes, totalSupply)) {
                revert ProposalRequirementsNotMet(_msgSender());
            }
        }
        return super.propose(targets, values, calldatas, description);
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override returns (uint256 proposalId) {
        proposalId = super._propose(targets, values, calldatas, description, proposer);
        if (address(proposalRequirements) != address(0)) {
            proposalRequirements.onProposalCreated(proposalId, proposer);
        }
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
