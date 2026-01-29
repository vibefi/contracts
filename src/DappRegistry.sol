// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

contract DappRegistry is AccessControl {
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant SECURITY_COUNCIL_ROLE = keccak256("SECURITY_COUNCIL_ROLE");

    enum VersionStatus {
        None,
        Published,
        Paused,
        Deprecated
    }

    struct DappVersion {
        bytes rootCid;
        VersionStatus status;
        address proposer;
        uint48 createdAt;
    }

    uint256 public nextDappId;

    mapping(uint256 dappId => mapping(uint256 versionId => DappVersion)) private _versions;
    mapping(uint256 dappId => uint256 latestVersionId) private _latestVersionId;

    event DappPublished(uint256 indexed dappId, uint256 indexed versionId, bytes rootCid, address proposer);
    event DappUpgraded(
        uint256 indexed dappId,
        uint256 indexed fromVersionId,
        uint256 indexed toVersionId,
        bytes rootCid,
        address proposer
    );
    event DappMetadata(
        uint256 indexed dappId, uint256 indexed versionId, string name, string version, string description
    );
    event DappPaused(uint256 indexed dappId, uint256 indexed versionId, address pausedBy, string reason);
    event DappUnpaused(uint256 indexed dappId, uint256 indexed versionId, address unpausedBy, string reason);
    event DappDeprecated(uint256 indexed dappId, uint256 indexed versionId, address deprecatedBy, string reason);

    error DappVersionNotFound(uint256 dappId, uint256 versionId);
    error InvalidRootCid();
    error InvalidStatusTransition(VersionStatus current, VersionStatus next);

    constructor(address governance, address securityCouncil) {
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GOVERNANCE_ROLE, governance);
        _grantRole(SECURITY_COUNCIL_ROLE, securityCouncil);
    }

    modifier onlyGovernance() {
        _checkRole(GOVERNANCE_ROLE, _msgSender());
        _;
    }

    modifier onlyCouncilOrGovernance() {
        if (!hasRole(GOVERNANCE_ROLE, _msgSender()) && !hasRole(SECURITY_COUNCIL_ROLE, _msgSender())) {
            revert AccessControlUnauthorizedAccount(_msgSender(), GOVERNANCE_ROLE);
        }
        _;
    }

    function latestVersionId(uint256 dappId) external view returns (uint256) {
        return _latestVersionId[dappId];
    }

    function getDappVersion(uint256 dappId, uint256 versionId)
        external
        view
        returns (bytes memory rootCid, VersionStatus status, address proposer, uint48 createdAt)
    {
        DappVersion storage version = _versions[dappId][versionId];
        if (version.status == VersionStatus.None) {
            revert DappVersionNotFound(dappId, versionId);
        }
        return (version.rootCid, version.status, version.proposer, version.createdAt);
    }

    function publishDapp(
        bytes calldata rootCid,
        string calldata name,
        string calldata version,
        string calldata description
    ) external onlyGovernance returns (uint256 dappId, uint256 versionId) {
        if (rootCid.length == 0) {
            revert InvalidRootCid();
        }
        dappId = ++nextDappId;
        versionId = 1;
        _writeVersion(dappId, versionId, rootCid, VersionStatus.Published, _msgSender());
        emit DappPublished(dappId, versionId, rootCid, _msgSender());
        emit DappMetadata(dappId, versionId, name, version, description);
    }

    function upgradeDapp(
        uint256 dappId,
        bytes calldata rootCid,
        string calldata name,
        string calldata version,
        string calldata description
    ) external onlyGovernance returns (uint256 versionId) {
        if (rootCid.length == 0) {
            revert InvalidRootCid();
        }
        uint256 fromVersionId = _latestVersionId[dappId];
        if (fromVersionId == 0) {
            revert DappVersionNotFound(dappId, 0);
        }
        versionId = fromVersionId + 1;
        _writeVersion(dappId, versionId, rootCid, VersionStatus.Published, _msgSender());
        emit DappUpgraded(dappId, fromVersionId, versionId, rootCid, _msgSender());
        emit DappMetadata(dappId, versionId, name, version, description);
    }

    function pauseDappVersion(uint256 dappId, uint256 versionId, string calldata reason)
        external
        onlyCouncilOrGovernance
    {
        DappVersion storage version = _requireVersion(dappId, versionId);
        if (version.status != VersionStatus.Published) {
            revert InvalidStatusTransition(version.status, VersionStatus.Paused);
        }
        version.status = VersionStatus.Paused;
        emit DappPaused(dappId, versionId, _msgSender(), reason);
    }

    function unpauseDappVersion(uint256 dappId, uint256 versionId, string calldata reason)
        external
        onlyCouncilOrGovernance
    {
        DappVersion storage version = _requireVersion(dappId, versionId);
        if (version.status != VersionStatus.Paused) {
            revert InvalidStatusTransition(version.status, VersionStatus.Published);
        }
        version.status = VersionStatus.Published;
        emit DappUnpaused(dappId, versionId, _msgSender(), reason);
    }

    function deprecateDappVersion(uint256 dappId, uint256 versionId, string calldata reason)
        external
        onlyCouncilOrGovernance
    {
        DappVersion storage version = _requireVersion(dappId, versionId);
        if (version.status == VersionStatus.Deprecated) {
            revert InvalidStatusTransition(version.status, VersionStatus.Deprecated);
        }
        version.status = VersionStatus.Deprecated;
        emit DappDeprecated(dappId, versionId, _msgSender(), reason);
    }

    function _writeVersion(
        uint256 dappId,
        uint256 versionId,
        bytes calldata rootCid,
        VersionStatus status,
        address proposer
    ) internal {
        DappVersion storage version = _versions[dappId][versionId];
        version.rootCid = rootCid;
        version.status = status;
        version.proposer = proposer;
        version.createdAt = uint48(block.timestamp);
        _latestVersionId[dappId] = versionId;
    }

    function _requireVersion(uint256 dappId, uint256 versionId) internal view returns (DappVersion storage) {
        DappVersion storage version = _versions[dappId][versionId];
        if (version.status == VersionStatus.None) {
            revert DappVersionNotFound(dappId, versionId);
        }
        return version;
    }
}
