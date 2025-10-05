//SPDX-License-Identifier:MIT
pragma solidity ^0.8.0;

import {Pool} from "src/Pool.sol";
import {CollateralManager} from "src/CollateralManager.sol";

contract Borrowing is Pool {
    CollateralManager collateralManager;

    modifier ensureEnoughCollateralForLoan(uint256 amount, address user) {
        require(userTotalBalance[user] * 2 >= amount / 3, "Insufficient Balance for loan collateral (150% is required)");
        _;
    }
    // This function locks 150% of the value of token borrowed from the token supplied by the caller
    // Transfers the stable coin the caller wants to borrow to their address
    // This function can only be called if the value of caller's tokens in the pool is up to 150% of the value of the token they want to borrow
    // The interest on the loan changes dynamically according to the availaility of collaterals
    // The loan grows as the interest accumulates
    // Collateral gets liquidated the moment the value drops to 120% of the loan borrowed

    function borrow(uint256 amount) private ensureEnoughCollateralForLoan(amount, msg.sender) {
        collateralManager.lockAsCollateral((amount * 3) / 2, msg.sender);
    }

    // This function transfers the stable coin borrowed from the caller's address to the pool
    // Unlocks the collateral back
    function repay() private {}
}
