// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VfiToken} from "../src/VfiToken.sol";

contract VfiTokenTest is Test {
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function testConstructorMintsInitialSupplyToHolder() public {
        VfiToken token = new VfiToken("VibeFi", "VFI", 1_000e18, alice);
        assertEq(token.totalSupply(), 1_000e18);
        assertEq(token.balanceOf(alice), 1_000e18);
    }

    function testConstructorSkipsMintWhenHolderIsZeroAddress() public {
        VfiToken token = new VfiToken("VibeFi", "VFI", 1_000e18, address(0));
        assertEq(token.totalSupply(), 0);
    }

    function testConstructorSkipsMintWhenSupplyIsZero() public {
        VfiToken token = new VfiToken("VibeFi", "VFI", 0, alice);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testDelegatedVotesTrackTransfers() public {
        VfiToken token = new VfiToken("VibeFi", "VFI", 1_000e18, alice);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1_000e18);

        vm.prank(alice);
        token.transfer(bob, 250e18);
        assertEq(token.getVotes(alice), 750e18);
        assertEq(token.getVotes(bob), 0);

        vm.prank(bob);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 250e18);
    }
}
