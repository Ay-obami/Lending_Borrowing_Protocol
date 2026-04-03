// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {InterestCalculator} from "./InterestCalculator.sol";

contract CollateralManager {
    /*
    InterestCalculator public supplyInterestCalculator;
    address public liquidationManager;
    uint256 public constant RAY = 1e18;
    uint256 public totalScaledDeposits;

    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public lockedCollateralBalances;

    constructor(
        uint256 _baseInterestRate,
        uint256 _optimalUtilizationRate,
        uint256 _slope1,
        uint256 _slope2,
        uint256 _reserveFactor,
        bool _isSupplyInterestCalculator,
        address _liquidationManager
    ) {
        liquidationManager = _liquidationManager;
        supplyInterestCalculator = new InterestCalculator(
            _baseInterestRate, _optimalUtilizationRate, _slope1, _slope2, _reserveFactor, _isSupplyInterestCalculator
        );
    }

    function deposit(uint256 amount, uint256 utilizationRate) external {
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        collateralBalances[msg.sender] += scaledAmount;
        totalScaledDeposits += scaledAmount;
    }

    function withdraw(uint256 amount, uint256 utilizationRate) external {
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(collateralBalances[msg.sender] >= scaledAmount, "Insufficient balance");
        collateralBalances[msg.sender] -= scaledAmount;
        totalScaledDeposits -= scaledAmount;
    }

    function forceWithdraw(address borrower, uint256 amount, uint256 utilizationRate) external {
        require(msg.sender == liquidationManager, "Not authorized");
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(lockedCollateralBalances[borrower] >= scaledAmount, "Insufficient locked collateral");
        lockedCollateralBalances[borrower] -= scaledAmount;
        totalScaledDeposits -= scaledAmount;
    }

    function lockCollateral(address user, uint256 amount, uint256 utilizationRate) external {
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(collateralBalances[user] >= scaledAmount, "Insufficient collateral");
        collateralBalances[user] -= scaledAmount;
        lockedCollateralBalances[user] += scaledAmount;
    }

    function unlockCollateral(address user, uint256 amount, uint256 utilizationRate) external {
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(lockedCollateralBalances[user] >= scaledAmount, "Insufficient locked collateral");
        lockedCollateralBalances[user] -= scaledAmount;
        collateralBalances[user] += scaledAmount;
    }

    function getUserBalance(address user, uint256 utilizationRate) external view returns (uint256) {
        return supplyInterestCalculator.getBalance(collateralBalances[user], utilizationRate);
    }

    function getPoolBalance() public view returns (uint256) {
        return totalScaledDeposits * supplyInterestCalculator.getLiquidityIndex() / 1e18;
    }

    function getTotalDepositsWithInterest(uint256 utilizationRate) external view returns (uint256) {
        return supplyInterestCalculator.getBalance(totalScaledDeposits, utilizationRate); // fix: use scaled total
    }
    */

    }
