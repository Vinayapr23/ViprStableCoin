//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ViprStableCoin} from "./ViprStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title VSCEngine
 * @author Vinaya Prasad R
 *
 * This contract powers a decentralized stablecoin system that aims to maintain a 1:1 peg with the US dollar.
 * The system is intentionally minimal, designed with the following characteristics:
 * - Backed by external collateral (exogenous)
 * - Pegged to the US dollar
 * - Maintains stability through algorithmic mechanisms
 *
 * It functions similarly to DAI, but with key differences:
 * - No governance
 * - No fees
 * - Collateralized exclusively by WETH and WBTC
 *
 * The system is designed to always remain overcollateralized — meaning the total value of all collateral
 * should always exceed the total value of all ViprStableCoin tokens in circulation.
 *
 * @notice This is the core contract of the Stablecoin system. It manages the minting and burning
 * of ViprStableCoin tokens, as well as the depositing and withdrawing of collateral.
 * @notice Inspired by the MakerDAO DSS system and inspired by Cryfin
 */

contract VSCEngine is ReentrancyGuard {
    ////////////////////////////////////
    //              Errors            //
    ///////////////////////////////////
    error VSCEngine__MustBeGreaterThanZero();

    error VSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSame();

    error VSCEngine__NotAllowedToken();

    error VSCEngine__TransferFailed();

    error VSCEngine__MintFailed();

    error VSC__BreaksEngineHealthFactor(uint256 healthFactor);

    // address public immutable VSC;
    // address public immutable WETH;
    // address public immutable WBTC;

    ////////////////////////////////////
    //      State Varibales           //
    ///////////////////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    mapping(address token => address priceFeeds) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //userToCollateral
    mapping(address user => uint256 amountVSCMinted) private s_VSCMinted; //userToVSCMinted
    address[] private s_collateralTokens; //list of collateral tokens
    ViprStableCoin private immutable i_vsc;

    ////////////////////////////////////
    //              Events            //
    ///////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////////////////////
    //              Modifiers         //
    ///////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert VSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert VSCEngine__NotAllowedToken();
        }
        _;
    }
    ////////////////////////////////////
    //              Constructor       //
    ///////////////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address vscAddress) {
        if (tokenAddresses.length == priceFeedAddresses.length) {
            revert VSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSame();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_vsc = ViprStableCoin(vscAddress);
    }

    ////////////////////////////////////
    //              Functions         //
    ///////////////////////////////////

    function depositCollateralAndMintVSC() external {}

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // Transfer the collateral from the user to the contract
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert VSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForVSC() external {}

    function redeemCollateral() external {}

    //check if collateral is enough to mint VSC
    /*
     * @param amountVSCToMint: The amount of VSC you want to mint
     * You can only mint VSC if you have enough collateral
     */
    function mintVSC(uint256 amountVSCToMint) external moreThanZero(amountVSCToMint) nonReentrant {
        s_VSCMinted[msg.sender] += amountVSCToMint;
        //if they min too much VSC, revert

        _revertIfHealthFacctorIsBroken(msg.sender);
        bool minted = i_vsc.mint(msg.sender, amountVSCToMint);
        if (!minted) {
            revert VSCEngine__MintFailed();
        }
    }

    function burnVSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ////////////////////////////////////////////
    //      Private & Internal View functions  //
    ////////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalVscMinted, uint256 collateralValueInUsd)
    {
        totalVscMinted = s_VSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*
    *Returns how close user is toliquidation
    *If user gets below 1, they are in danger of liquidation
    */
    function _healthFactor(address user) private view returns (uint256) {
        //total VSC minted
        //total collateral value

        (uint256 totalVscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //200% collateralized

        //$1000 ETH * 50 = 50000/100 =500 VSC
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        //1000 dollar ETH /100 VSC
        //1000 *50 =50000/100 =500
        // 500/100 =5

        //if less than 1, you are f*cked
        return (collateralAdjustedForThreshold * PRECISION) / totalVscMinted;
    }

    function _revertIfHealthFacctorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert VSC__BreaksEngineHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////
    //      Public & External  View           //
    ////////////////////////////////////////////

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }
}
