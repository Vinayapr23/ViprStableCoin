// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ViprStableCoin} from "../src/ViprStableCoin.sol";
import {VSCEngine} from "../src/VSCEngine.sol";

contract DeployVSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (ViprStableCoin, VSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();

        ViprStableCoin vsc = new ViprStableCoin();
        VSCEngine engine = new VSCEngine(tokenAddresses, priceFeedAddresses, address(vsc));

        vsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (vsc, engine, helperConfig);
    }
}
