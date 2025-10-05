// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Pool {
    error amountShouldBeGreaterThanZero(string);
    error transferFailed(string);
    error insufficientBalance(string);
    error withdrawalFailed(string);
    //IERC20 erc20 = IERC20 (address token);

    address btc;
    address eth;
    address lockedPool;
    mapping(address => uint256) userTotalBalance;
    mapping(address => uint256) poolTotalBalance;

    event transferSuccessful(address, uint256);
    event withdrawalSuccessful(address, uint256);

    modifier mustBeGreaterThanZero(uint256 amount) {
        if (amount <= 0) {
            revert amountShouldBeGreaterThanZero("Amount should be more than zero");
        }
        _;
    }

    modifier balanceMustBeSufficient(uint256 amount, address user) {
        require(userTotalBalance[user] >= amount, "Insufficient Balance");
        _;
    }

    //This function transfers tokens to the pool from the caller's address and mints a corresponding amount of virtual token to the caller's address
    function supplyEth(uint256 amount, address poolAddress) internal mustBeGreaterThanZero(amount) {
        userTotalBalance[msg.sender] -= amount;
        poolTotalBalance[poolAddress] += amount;
        emit transferSuccessful(msg.sender, amount);
        IERC20 wEth = IERC20(eth);
        bool successful = wEth.transferFrom(msg.sender, poolAddress, amount);
        if (!successful) {
            revert transferFailed("Transfer Failed");
        }
    }

    function supplyBtc(uint256 amount, address poolAddress) internal mustBeGreaterThanZero(amount) {
        userTotalBalance[msg.sender] -= amount;
        poolTotalBalance[poolAddress] += amount;
        emit transferSuccessful(msg.sender, amount);
        IERC20 wBtc = IERC20(btc);
        bool successful = wBtc.transferFrom(msg.sender, poolAddress, amount);
        if (!successful) {
            revert transferFailed("Transfer Failed");
        }
    }
    // This function transfers tokens from the pool to the caller's address and burns a corresponding amount of virtual token from the caller's address
    // This can only be called by an address that has supplied tokens to the pool
    // Caller can't withdraw locked tokens i.e tokens that has been locked as collateral
    // Tokens locked as collateral accumulates interest

    function withdrawEth(uint256 amount, address poolAddress) internal mustBeGreaterThanZero(amount) {
        userTotalBalance[msg.sender] += amount;
        poolTotalBalance[poolAddress] -= amount;
        emit transferSuccessful(msg.sender, amount);
        IERC20 wEth = IERC20(eth);
        bool successful = wEth.transfer(msg.sender, amount);
        if (!successful) {
            revert withdrawalFailed("Withdrawal Failed");
        }
    }

    function withdrawBtc(uint256 amount, address poolAddress) internal mustBeGreaterThanZero(amount) {
        userTotalBalance[msg.sender] += amount;
        poolTotalBalance[poolAddress] -= amount;
        emit transferSuccessful(msg.sender, amount);
        IERC20 wBtc = IERC20(btc);
        bool successful = wBtc.transfer(msg.sender, amount);
        if (!successful) {
            revert withdrawalFailed("Withdrawal Failed");
        }
    }

    function setHealthFactor() private {}
    function getHealthFactor() public {}
}
