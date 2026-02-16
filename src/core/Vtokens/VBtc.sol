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

import {ERC20Burnable, ERC20} from "src/core/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vbtc is ERC20Burnable, Ownable {
    error Vbtc__AmountMustBeMoreThanZero();
    error Vbtc__BurnAmountExceedsBalance();
    error Vbtc__NotZeroAddress();

    constructor() ERC20("Virtual BTC", "Vbtc") Ownable(msg.sender) {}

    function burn(address user, uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(user);
        if (_amount <= 0) {
            revert Vbtc__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert Vbtc__BurnAmountExceedsBalance();
        }
        super.burn(user, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Vbtc__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert Vbtc__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
