// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ViprStableCoin} from "../../src/ViprStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract ViprStablecoinTest is StdCheats, Test {
    ViprStableCoin vsc;

    function setUp() public {
        vsc = new ViprStableCoin();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(vsc.owner());
        vm.expectRevert();
        vsc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(vsc.owner());
        vsc.mint(address(this), 100);
        vm.expectRevert();
        vsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        // First, transfer ownership to the test contract
        address originalOwner = vsc.owner();
        vm.prank(originalOwner);
        vsc.transferOwnership(address(this));

        // Now, make sure this contract has exactly 100 tokens
        // (Clear any existing balance first by burning it)
        uint256 currentBalance = vsc.balanceOf(address(this));
        if (currentBalance > 100) {
            vsc.burn(currentBalance - 100);
        } else if (currentBalance < 100) {
            vsc.mint(address(this), 100 - currentBalance);
        }

        // Now try to burn more than we have
        vm.expectRevert(ViprStableCoin.ViprStableCoin__BurnAmountExceedsBalance.selector);
        vsc.burn(101);
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(vsc.owner());
        vm.expectRevert();
        vsc.mint(address(0), 100);
        vm.stopPrank();
    }
}
