// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InterestCalculator {
    uint256 public baseInterestRate;
    uint256 public reserveFactor; // Portion of interest that goes to reserves
    uint256 public lastUpdated;
    uint256 public optimalUtilizationRate;
    uint256 public slope1;
    uint256 public slope2;
    uint256 public liquidityIndex;
    uint256 public constant RAY = 1e18;
    uint256 public constant YEAR_IN_SECONDS = 365 * 24 * 60 * 60;
    bool public immutable isSupplyInterestCalculator; // true for supply, false for borrow

    constructor(
        uint256 _baseInterestRate,
        uint256 _optimalUtilizationRate,
        uint256 _slope1,
        uint256 _slope2,
        uint256 _reserveFactor,
        bool _isSupplyInterestCalculator
    ) {
        baseInterestRate = _baseInterestRate;
        lastUpdated = block.timestamp;
        optimalUtilizationRate = _optimalUtilizationRate;
        slope1 = _slope1;
        slope2 = _slope2;
        liquidityIndex = RAY;
        isSupplyInterestCalculator = _isSupplyInterestCalculator;
        reserveFactor = _reserveFactor;
    }

    function getCurrentInterestRate(uint256 utilizationRate) public view returns (uint256) {
        uint256 interestRate;
        if (utilizationRate <= optimalUtilizationRate) {
            interestRate = baseInterestRate + (utilizationRate * slope1) / optimalUtilizationRate;
        } else {
            uint256 excessUtil = utilizationRate - optimalUtilizationRate;
            uint256 remainingUtil = RAY - optimalUtilizationRate;
            interestRate = baseInterestRate + slope1 + (excessUtil * slope2) / remainingUtil;
        }
        if (isSupplyInterestCalculator) {
            return interestRate * utilizationRate * (RAY - reserveFactor) / RAY / RAY; // Adjust for reserve factor
        } else {
            return interestRate; // Borrowers pay the full rate
        }
    }

    function updateLiquidityIndex(uint256 utilizationRate) public {
        uint256 timeElapsed = block.timestamp - lastUpdated;
        if (timeElapsed == 0) return;

        uint256 rate = getCurrentInterestRate(utilizationRate);
        uint256 growth = RAY + (rate * timeElapsed / YEAR_IN_SECONDS);
        liquidityIndex = liquidityIndex * growth / RAY;
        lastUpdated = block.timestamp;
    }

    function getBalance(uint256 userScaledBalance, uint256 utilizationRate) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdated;
        uint256 rate = getCurrentInterestRate(utilizationRate);
        uint256 currentIndex = liquidityIndex * (RAY + rate * timeElapsed / YEAR_IN_SECONDS) / RAY;
        return userScaledBalance * currentIndex / RAY;
    }
}
