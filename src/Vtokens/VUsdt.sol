// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.0;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vusdt is ERC20Burnable, Ownable {
    error Vusdt__AmountMustBeMoreThanZero();
    error Vusdt__BurnAmountExceedsBalance();
    error Vusdt__NotZeroAddress();

    constructor() ERC20("Virtual USDT", "Vusdt") Ownable(msg.sender) {}

    function burn(address user, uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(user);
        if (_amount <= 0) {
            revert Vusdt__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert Vusdt__BurnAmountExceedsBalance();
        }
        super.burn(user, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Vusdt__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert Vusdt__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function totalSupply() public view override returns (uint256) {
        uint256 totalUsdtSupplied = super.totalSupply();
        return totalUsdtSupplied;
    }
}
