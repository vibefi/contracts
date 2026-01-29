// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VfiToken} from "../src/VfiToken.sol";
import {VfiGovernor} from "../src/VfiGovernor.sol";
import {VfiTimelock} from "../src/VfiTimelock.sol";
import {DappRegistry} from "../src/DappRegistry.sol";
import {MinimumDelegationRequirement} from "../src/proposal/MinimumDelegationRequirement.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";

contract GovernanceIntegrationTest is Test {
    event DappPublished(uint256 indexed dappId, uint256 indexed versionId, bytes rootCid, address proposer);
    event DappMetadata(
        uint256 indexed dappId,
        uint256 indexed versionId,
        string name,
        string version,
        string description
    );
    event DappPaused(uint256 indexed dappId, uint256 indexed versionId, address pausedBy, string reason);
    event DappUnpaused(uint256 indexed dappId, uint256 indexed versionId, address unpausedBy, string reason);
    event SecurityCouncilVeto(uint256 indexed proposalId, address indexed vetoedBy);

    VfiToken private token;
    VfiGovernor private governor;
    VfiTimelock private timelock;
    DappRegistry private registry;
    MinimumDelegationRequirement private requirements;

    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    address private carol = address(0xCA11);
    address private securityCouncil = address(0x5EC);

    uint48 private votingDelay = 1;
    uint32 private votingPeriod = 5;
    uint256 private quorumFraction = 4;
    uint256 private minDelay = 1;

    function setUp() public {
        uint256 totalSupply = 1_000_000e18;
        token = new VfiToken("VibeFi", "VFI", totalSupply, address(this));

        token.transfer(alice, 600_000e18);
        token.transfer(bob, 300_000e18);
        token.transfer(carol, 100_000e18);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new VfiTimelock(minDelay, proposers, executors, address(this));

        requirements = new MinimumDelegationRequirement(100); // 1% in BPS
        governor = new VfiGovernor(
            token,
            timelock,
            votingDelay,
            votingPeriod,
            0,
            quorumFraction,
            requirements,
            securityCouncil
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        registry = new DappRegistry(address(timelock), securityCouncil);

        vm.roll(block.number + 1);
    }

    function testDaoVotingPublishesDappAndEmitsEvents() public {
        bytes memory cid = hex"01701220";
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _publishProposal(cid, "Uniswap", "1.0.0", "Swap UI");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + votingDelay + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 0);
        vm.prank(carol);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + votingPeriod + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + minDelay + 1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappPublished(1, 1, cid, address(timelock));

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappMetadata(1, 1, "Uniswap", "1.0.0", "Swap UI");

        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function testDaoRejectionDoesNotPublish() public {
        bytes memory cid = hex"01701220";
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _publishProposal(cid, "Scam", "0.1.0", "Rugpull UI");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + votingDelay + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 0);
        vm.prank(bob);
        governor.castVote(proposalId, 0);
        vm.prank(carol);
        governor.castVote(proposalId, 0);

        vm.roll(block.number + votingPeriod + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
        assertEq(registry.latestVersionId(1), 0);

        bytes32 descriptionHash = keccak256(bytes(description));
        vm.expectRevert();
        governor.queue(targets, values, calldatas, descriptionHash);
    }

    function testSecurityCouncilVetoCancelsProposal() public {
        bytes memory cid = hex"01701220";
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _publishProposal(cid, "Evil", "0.0.1", "Malicious UI");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        bytes32 descriptionHash = keccak256(bytes(description));

        vm.expectEmit(true, true, false, true, address(governor));
        emit SecurityCouncilVeto(proposalId, securityCouncil);

        vm.prank(securityCouncil);
        governor.vetoProposal(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function testSecurityCouncilPauseUnpauseEmitsEvents() public {
        bytes memory cid = hex"01701220";
        _publishDirect(cid, "Test", "1.0.0", "Demo");

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappPaused(1, 1, securityCouncil, "incident");
        vm.prank(securityCouncil);
        registry.pauseDappVersion(1, 1, "incident");

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappUnpaused(1, 1, securityCouncil, "resolved");
        vm.prank(securityCouncil);
        registry.unpauseDappVersion(1, 1, "resolved");
    }

    function _publishProposal(
        bytes memory cid,
        string memory name,
        string memory version,
        string memory summary
    ) internal view returns (address[] memory, uint256[] memory, bytes[] memory, string memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(registry);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            registry.publishDapp.selector,
            cid,
            name,
            version,
            summary
        );

        string memory description = string(abi.encodePacked("Publish ", name, " ", version));
        return (targets, values, calldatas, description);
    }

    function _publishDirect(
        bytes memory cid,
        string memory name,
        string memory version,
        string memory summary
    ) internal {
        vm.prank(address(timelock));
        registry.publishDapp(cid, name, version, summary);
    }
}
