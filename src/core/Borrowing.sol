// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InterestCalculator} from "./InterestCalculator.sol";

contract Borrowing {
    using SafeERC20 for IERC20;

    InterestCalculator public borrowInterestCalculator;
    IERC20 public borrowedToken;
    uint256 public constant RAY = 1e18;
    uint256 public totalScaledBorrowed;

    mapping(address => uint256) public scaledBorrowedAmounts;

    constructor(address _borrowedToken) {
        borrowedToken = IERC20(_borrowedToken);
        borrowInterestCalculator = new InterestCalculator(0.1e18, 0.8e18, 0.1e18, 0.2e18, 0.1e18, false);
    }

    function borrow(address borrower, uint256 amount, uint256 utilizationRate) external {
        borrowInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = borrowInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(scaledAmount > 0, "Invalid borrow amount");
        scaledBorrowedAmounts[borrower] += scaledAmount;
        totalScaledBorrowed += scaledAmount;
        borrowedToken.safeTransfer(borrower, amount);
    }

    function repay(address borrower, uint256 amount, uint256 utilizationRate) external {
        borrowInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = borrowInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(scaledAmount > 0, "Invalid repay amount");
        require(scaledBorrowedAmounts[borrower] >= scaledAmount, "Repay amount exceeds borrowed amount");
        borrowedToken.safeTransferFrom(borrower, address(this), amount);
        totalScaledBorrowed -= scaledAmount;
        scaledBorrowedAmounts[borrower] -= scaledAmount;
    }

    function getInterestRate(uint256 utilizationRate) external view returns (uint256) {
        return borrowInterestCalculator.getCurrentInterestRate(utilizationRate);
    }

    function getLoanBalance(address borrower, uint256 utilizationRate) external view returns (uint256) {
        return borrowInterestCalculator.getBalance(scaledBorrowedAmounts[borrower], utilizationRate);
    }

    function getTotalBorrowed(uint256 utilizationRate) external view returns (uint256) {
        return borrowInterestCalculator.getBalance(totalScaledBorrowed, utilizationRate);
    }
}
