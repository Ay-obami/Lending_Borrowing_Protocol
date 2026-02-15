//SPDX-License-Identifier:MIT
pragma solidity ^0.8.0;

import {Pool} from "src/Pool.sol";
import {CollateralManager} from "src/CollateralManager.sol";

contract Borrowing {
    CollateralManager collateralManager;
    Pool pool;

    // This function locks 150% of the value of token borrowed from the token supplied by the caller
    // Transfers the stable coin the caller wants to borrow to their address
    // This function can only be called if the value of caller's tokens in the pool is up to 150% of the value of the token they want to borrow
    // The interest on the loan changes dynamically according to the availaility of collaterals
    // The loan grows as the interest accumulates
    // Collateral gets liquidated the moment the value drops to 120% of the loan borrowed

    function borrowWithEthAsCollateral(uint256 usdtAmount) private {
        require(
            collateralManager.getEthCollateralValueInUsd(msg.sender) * 2 >= usdtAmount / 3,
            "Insufficient Balance for loan collateral (150% is required)"
        );
        uint256 ethPrice = collateralManager.getEthPrice();
        uint256 ethValueToBeLocked = ((usdtAmount * 3) / (ethPrice / 2));
        collateralManager.lockEthCollateral(ethValueToBeLocked, msg.sender);
        pool.borrowUsdt(usdtAmount);
    }

    function borrowWithBtcAsCollateral(uint256 usdtAmount) private {
        require(
            collateralManager.getBtcCollateralValueInUsd(msg.sender) * 2 >= usdtAmount / 3,
            "Insufficient Balance for loan collateral (150% is required)"
        );
        uint256 btcPrice = collateralManager.getBtcPrice();
        uint256 btcValueToBeLocked = ((usdtAmount * 3) / (btcPrice / 2));
        collateralManager.lockBtcCollateral(btcValueToBeLocked, msg.sender);
        pool.borrowUsdt(usdtAmount);
    }

    // This function transfers the stable coin borrowed from the caller's address to the pool
    // Unlocks the collateral back when loan is fully paid
    function repayLoanWithBtcAsCollateral(uint256 usdtAmount) private {
        pool.payUsdt(usdtAmount);
        uint256 loanBalance = pool.getLoanBalance(msg.sender);
        if (loanBalance <= 0) {
            uint256 presentCollateralBalance = collateralManager.getLockedBtcBalance(msg.sender);
            collateralManager.unlockBtcCollateral(presentCollateralBalance, msg.sender);
        }
    }

    function repayLoanWithEThAsCollateral(uint256 usdtAmount) private {
        pool.payUsdt(usdtAmount);
        uint256 loanBalance = pool.getLoanBalance(msg.sender);
        if (loanBalance <= 0) {
            uint256 presentCollateralBalance = collateralManager.getLockedEthBalance(msg.sender);
            collateralManager.unlockEthCollateral(presentCollateralBalance, msg.sender);
        }
    }
}
