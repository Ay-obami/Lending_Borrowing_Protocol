// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {InterestCalculator} from "./InterestCalculator.sol";

contract CollateralManager {
    using SafeERC20 for IERC20;

    IERC20 public collateralToken;
    InterestCalculator public supplyInterestCalculator;
    address public liquidationManager;
    uint256 public constant RAY = 1e18;
    uint256 public totalScaledDeposits;

    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public lockedCollateralBalances;

    constructor(address _collateralToken, address _liquidationManager) {
        collateralToken = IERC20(_collateralToken);
        liquidationManager = _liquidationManager;
        supplyInterestCalculator = new InterestCalculator(0.1e18, 0.8e18, 0.1e18, 0.2e18, 0.1e18, true);
    }

    function deposit(uint256 amount, uint256 utilizationRate) external {
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
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
        collateralToken.safeTransfer(msg.sender, amount);
    }

    function forceWithdraw(address borrower, uint256 amount, uint256 utilizationRate) external {
        require(msg.sender == liquidationManager, "Not authorized");
        supplyInterestCalculator.updateLiquidityIndex(utilizationRate);
        uint256 liquidityIndex = supplyInterestCalculator.getLiquidityIndex();
        uint256 scaledAmount = amount * RAY / liquidityIndex;
        require(lockedCollateralBalances[borrower] >= scaledAmount, "Insufficient locked collateral");
        lockedCollateralBalances[borrower] -= scaledAmount;
        totalScaledDeposits -= scaledAmount;
        collateralToken.safeTransfer(msg.sender, amount);
    }

    function lockCollateral(uint256 amount) external {
        require(collateralBalances[msg.sender] >= amount, "Insufficient collateral");
        collateralBalances[msg.sender] -= amount;
        lockedCollateralBalances[msg.sender] += amount;
    }

    function unlockCollateral(uint256 amount) external {
        require(lockedCollateralBalances[msg.sender] >= amount, "Insufficient locked collateral");
        lockedCollateralBalances[msg.sender] -= amount;
        collateralBalances[msg.sender] += amount;
    }

    function getUserBalance(address user, uint256 utilizationRate) external view returns (uint256) {
        return supplyInterestCalculator.getBalance(collateralBalances[user], utilizationRate);
    }

    function getPoolBalance() public view returns (uint256) {
        return collateralToken.balanceOf(address(this));
    }

    function getTotalDepositsWithInterest(uint256 utilizationRate) external view returns (uint256) {
        return supplyInterestCalculator.getBalance(totalScaledDeposits, utilizationRate); // fix: use scaled total
    }
}
