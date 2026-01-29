// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

contract ConstraintsRegistry is AccessControl {
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    mapping(bytes32 constraintsId => bytes rootCid) private _constraints;

    event ConstraintsUpdated(bytes32 indexed constraintsId, bytes rootCid, address updatedBy);

    error InvalidRootCid();

    constructor(address governance) {
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GOVERNANCE_ROLE, governance);
    }

    function getConstraints(bytes32 constraintsId) external view returns (bytes memory) {
        return _constraints[constraintsId];
    }

    function setConstraints(bytes32 constraintsId, bytes calldata rootCid) external onlyRole(GOVERNANCE_ROLE) {
        if (rootCid.length == 0) {
            revert InvalidRootCid();
        }
        _constraints[constraintsId] = rootCid;
        emit ConstraintsUpdated(constraintsId, rootCid, _msgSender());
    }
}
