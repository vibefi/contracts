// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VfiToken} from "../src/VfiToken.sol";
import {VfiGovernor} from "../src/VfiGovernor.sol";
import {VfiTimelock} from "../src/VfiTimelock.sol";
import {DappRegistry} from "../src/DappRegistry.sol";
import {ConstraintsRegistry} from "../src/ConstraintsRegistry.sol";
import {MinimumDelegationRequirement} from "../src/proposal/MinimumDelegationRequirement.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";

contract GovernanceIntegrationTest is Test {
    event DappPublished(uint256 indexed dappId, uint256 indexed versionId, bytes rootCid, address proposer);
    event DappMetadata(
        uint256 indexed dappId, uint256 indexed versionId, string name, string version, string description
    );
    event DappPaused(uint256 indexed dappId, uint256 indexed versionId, address pausedBy, string reason);
    event DappUnpaused(uint256 indexed dappId, uint256 indexed versionId, address unpausedBy, string reason);
    event SecurityCouncilVeto(uint256 indexed proposalId, address indexed vetoedBy);
    event DappUpgraded(
        uint256 indexed dappId,
        uint256 indexed fromVersionId,
        uint256 indexed toVersionId,
        bytes rootCid,
        address proposer
    );
    event DappDeprecated(uint256 indexed dappId, uint256 indexed versionId, address deprecatedBy, string reason);
    event ConstraintsUpdated(bytes32 indexed constraintsId, bytes rootCid, address updatedBy);

    VfiToken private token;
    VfiGovernor private governor;
    VfiTimelock private timelock;
    DappRegistry private registry;
    ConstraintsRegistry private constraintsRegistry;
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
            token, timelock, votingDelay, votingPeriod, 0, quorumFraction, requirements, securityCouncil
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        registry = new DappRegistry(address(timelock), securityCouncil);
        constraintsRegistry = new ConstraintsRegistry(address(timelock));

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

    function testDaoUpgradesAndDeprecatesDapp() public {
        bytes memory cidV1 = hex"01701220";
        bytes memory cidV2 = hex"01701221";

        (address[] memory pubTargets, uint256[] memory pubValues, bytes[] memory pubCalldatas, string memory pubDesc) =
            _publishProposal(cidV1, "Pool", "1.0.0", "Pool UI");
        _executeProposal(pubTargets, pubValues, pubCalldatas, pubDesc);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _upgradeProposal(1, cidV2, "Pool", "1.1.0", "Pool UI v2");
        uint256 proposalId = _proposeAndPass(targets, values, calldatas, description);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + minDelay + 1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappUpgraded(1, 1, 2, cidV2, address(timelock));
        vm.expectEmit(true, true, true, true, address(registry));
        emit DappMetadata(1, 2, "Pool", "1.1.0", "Pool UI v2");

        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        (address[] memory depTargets, uint256[] memory depValues, bytes[] memory depCalldatas, string memory depDesc) =
            _deprecateProposal(1, 1, "superseded");
        uint256 depProposalId = _proposeAndPass(depTargets, depValues, depCalldatas, depDesc);
        bytes32 depHash = keccak256(bytes(depDesc));
        governor.queue(depTargets, depValues, depCalldatas, depHash);
        vm.warp(block.timestamp + minDelay + 1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit DappDeprecated(1, 1, address(timelock), "superseded");
        governor.execute(depTargets, depValues, depCalldatas, depHash);
        assertEq(uint256(governor.state(depProposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function testDaoUpdatesConstraintsRegistry() public {
        bytes32 constraintsId = keccak256("default");
        bytes memory cid = hex"01701299";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _constraintsProposal(constraintsId, cid);
        uint256 proposalId = _proposeAndPass(targets, values, calldatas, description);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + minDelay + 1);

        vm.expectEmit(true, true, true, true, address(constraintsRegistry));
        emit ConstraintsUpdated(constraintsId, cid, address(timelock));
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function _publishProposal(bytes memory cid, string memory name, string memory version, string memory summary)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(registry);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(registry.publishDapp.selector, cid, name, version, summary);

        string memory description = string(abi.encodePacked("Publish ", name, " ", version));
        return (targets, values, calldatas, description);
    }

    function _upgradeProposal(
        uint256 dappId,
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
        calldatas[0] = abi.encodeWithSelector(registry.upgradeDapp.selector, dappId, cid, name, version, summary);

        string memory description = string(abi.encodePacked("Upgrade ", name, " ", version));
        return (targets, values, calldatas, description);
    }

    function _deprecateProposal(uint256 dappId, uint256 versionId, string memory reason)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(registry);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(registry.deprecateDappVersion.selector, dappId, versionId, reason);

        string memory description =
            string(abi.encodePacked("Deprecate ", vm.toString(dappId), " ", vm.toString(versionId)));
        return (targets, values, calldatas, description);
    }

    function _constraintsProposal(bytes32 constraintsId, bytes memory cid)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(constraintsRegistry);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(constraintsRegistry.setConstraints.selector, constraintsId, cid);

        string memory description = "Update constraints";
        return (targets, values, calldatas, description);
    }

    function _proposeAndPass(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + votingDelay + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 0);
        vm.prank(carol);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + votingPeriod + 1);
    }

    function _executeProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        proposalId = _proposeAndPass(targets, values, calldatas, description);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + minDelay + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function _publishDirect(bytes memory cid, string memory name, string memory version, string memory summary)
        internal
    {
        vm.prank(address(timelock));
        registry.publishDapp(cid, name, version, summary);
    }
}
