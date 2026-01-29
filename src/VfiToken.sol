// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";

contract VfiToken is ERC20Votes {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address initialHolder
    ) ERC20(name_, symbol_) EIP712(name_, "1") {
        if (initialHolder != address(0) && initialSupply > 0) {
            _mint(initialHolder, initialSupply);
        }
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Votes) {
        super._update(from, to, value);
    }
}
