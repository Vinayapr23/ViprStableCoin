// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployVSC} from "../../script/DeployVSC.s.sol";
import {VSCEngine} from "../../src/VSCEngine.sol";
import {ViprStableCoin} from "../../src/ViprStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract VSCEngineTest is Test {
    VSCEngine public vsce;
    ViprStableCoin public vsc;
    HelperConfig public helperConfig;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    address public USER = makeAddr("user");
    uint256 public constant amountCollateral = 10 ether;

    function setUp() external {
        DeployVSC deployer = new DeployVSC();
        (vsc, vsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = vsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    ///////////////////////
    // Deposit Collateral //
    ///////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(vsce), amountCollateral);

        vm.expectRevert(VSCEngine.VSCEngine__MustBeGreaterThanZero.selector);
        vsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
