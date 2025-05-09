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

    error VSCEngine__HealthFactorOk();

    error VSCEngine__HealthFactorNotImproved();

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
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if
        // redeemFrom != redeemedTo, then it was liquidated
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
        if (tokenAddresses.length != priceFeedAddresses.length) {
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

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountVscToMint: The amount of VSC you want to mint
     * @notice This function will deposit your collateral and mint VSC in one transaction
     */
    function depositCollateralAndMintVSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountVscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintVSC(amountVscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're withdrawing
     * @param amountCollateral: The amount of collateral you're withdrawing
     * @param amountVscToBurn: The amount of VSC you want to burn
     * @notice This function will withdraw your collateral and burn VSC in one transaction
     */
    function redeemCollateralForVsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountVscToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnVsc(amountVscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFacctorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have VSC minted, you will not be able to redeem until you burn your DSC
     */

    //Health factor must be over 1 after collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFacctorIsBroken(msg.sender);
    }

    //

    //check if collateral is enough to mint VSC
    /*
     * @param amountVSCToMint: The amount of VSC you want to mint
     * You can only mint VSC if you have enough collateral
     */
    function mintVSC(uint256 amountVSCToMint) public moreThanZero(amountVSCToMint) nonReentrant {
        s_VSCMinted[msg.sender] += amountVSCToMint;
        //if they min too much VSC, revert

        _revertIfHealthFacctorIsBroken(msg.sender);
        bool minted = i_vsc.mint(msg.sender, amountVSCToMint);
        if (!minted) {
            revert VSCEngine__MintFailed();
        }
    }

    /*
     * @notice careful! You'll burn your VSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * your VSC but keep your collateral in.
     */

    function burnVsc(uint256 amount) external moreThanZero(amount) {
        _burnVsc(amount, msg.sender, msg.sender);
        _revertIfHealthFacctorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your VSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of VSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 200% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert VSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 VSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn VSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnVsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert VSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFacctorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////
    // Private Functions
    ///////////////////

    function _burnVsc(uint256 amountVscToBurn, address onBehalfOf, address vscFrom) private {
        s_VSCMinted[onBehalfOf] -= amountVscToBurn;

        bool success = i_vsc.transferFrom(vscFrom, address(this), amountVscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert VSCEngine__TransferFailed();
        }
        i_vsc.burn(amountVscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert VSCEngine__TransferFailed();
        }
    }

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

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getVsc() external view returns (address) {
        return address(i_vsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
