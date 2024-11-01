//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 *@title: ViprStableCoin
 *@author:Vinaya Prasad R
 *@description: This is a simple implementation of a Vipr Stable Coin (VSC) contract.
 * The VSC is a stablecoin that is pegged to USD
 *collateralzed by WETH and WBTC.
 *ERC 20 standard is used for the implementation.
 */

contract ViprStableCoin is ERC20Burnable, Ownable {
    error ViprStableCoin__MustBeGreaterThanZero();
    error ViprStableCoin__BurnAmountExceedsBalance();
    error ViprStableCoin__NotZeroAddress();

    constructor() ERC20("ViprStableCoin", "VSC") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert ViprStableCoin__MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert ViprStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount); //use the burn function from ERC20Burnable
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool{
        if (_to == address(0)) {
            revert ViprStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert ViprStableCoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
