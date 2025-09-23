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
    error amountShouldBeGreaterThanZero (string);
    error transferFailed (string);
    error insufficientBalance (string);
    error withdrawalFailed (string);
    IERC20 erc20;
    mapping (address => uint256) userTotalBalance;
    mapping (address => uint256) poolTotalBalance;
    event transferSuccessful (address, uint256);
    event withdrawalSuccessful (address, uint256);
    modifier mustBeGreaterThanZero (uint256 amount) {
        if (amount <= 0) {
            revert amountShouldBeGreaterThanZero("Amount should be more than zero");
        }_;
    }
    modifier balanceMustBeSufficient (uint256 amount, address user) {
        require (userTotalBalance[user] >= amount, "Insufficient Balance");
        _;
    }
    //This function transfers tokens to the pool from the caller's address and mints a corresponding amount of virtual token to the caller's address 
    function supply(uint256 amount, address poolAddress) internal mustBeGreaterThanZero(amount){
        userTotalBalance[msg.sender] -= amount;
        poolTotalBalance[poolAddress] += amount; 
        emit transferSuccessful (msg.sender, amount);
        bool successful = erc20.transferFrom(msg.sender, poolAddress, amount);
        if (!successful){
            revert transferFailed ("Transfer Failed");
        }
    }
    // This function transfers tokens from the pool to the caller's address and burns a corresponding amount of virtual token from the caller's address 
    // This can only be called by an address that has supplied tokens to the pool
    // Caller can't withdraw locked tokens i.e tokens that has been locked as collateral 
    // Tokens locked as collateral accumulates interest
    function withdraw(uint256 amount, address poolAddress) private balanceMustBeSufficient(amount, msg.sender){
        userTotalBalance[msg.sender] += amount;
        poolTotalBalance[poolAddress] -= amount;
        bool successful = erc20.transfer(poolAddress, amount);
        if (!successful){
            revert withdrawalFailed ("Withdrawal failed");
        }

        
    }
    // This function locks 150% of the value of token borrowed from the token supplied by the caller
    // Transfers the stable coin the caller wants to borrow to their address 
    // This function can only be called if the value of caller's tokens in the pool is up to 150% of the value of the token they want to borrow
    // The interest on the loan changes dynamically according to the availaility of collaterals
    // The loan grows as the interest accumulates 
    // Collateral gets liquidated the moment the value drops to 120% of the loan borrowed
    function borrow()private{}
    // This function transfers the stable coin borrowed from the caller's address to the pool
    // Unlocks the collateral back
    function repay() private{}
    //This function locks token as collateral 
    function lockAsCollateral () private {}
    //This function unlocks token as collateral 
    function unlockCollateral () private {}
    function setHealthFactor() private {}
    function getHealthFactor () public {}
    
    

}
