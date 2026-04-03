// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InterestCalculator {
    uint256 public constant RAY = 1e18;
    uint256 public constant YEAR_IN_SECONDS = 365 * 24 * 60 * 60;
    bool public immutable isSupply;

    constructor(bool _isSupply) {
        isSupply = _isSupply;
    }

    function getCurrentInterestRate(
        uint256 utilizationRate,
        uint256 slope1,
        uint256 slope2,
        uint256 baseInterestRate,
        uint256 optimalUtilizationRate,
        uint256 reserveFactor
    ) public view returns (uint256) {
        uint256 interestRate;
        if (utilizationRate <= optimalUtilizationRate) {
            interestRate = baseInterestRate + (utilizationRate * slope1) / optimalUtilizationRate;
        } else {
            uint256 excessUtil = utilizationRate - optimalUtilizationRate;
            uint256 remainingUtil = RAY - optimalUtilizationRate;
            interestRate = baseInterestRate + slope1 + (excessUtil * slope2) / remainingUtil;
        }

        if (isSupply) {
            return (interestRate * utilizationRate * (RAY - reserveFactor)) / RAY / RAY;
        } else {
            return interestRate;
        }
    }

    function computeUpdatedLiquidityIndex(
        uint256 currentLiquidityIndex,
        uint256 utilizationRate,
        uint256 timeElapsed,
        uint256 slope1,
        uint256 slope2,
        uint256 baseInterestRate,
        uint256 optimalUtilizationRate,
        uint256 reserveFactor
    ) public view returns (uint256) {
        if (timeElapsed == 0) return currentLiquidityIndex;
        uint256 rate = getCurrentInterestRate(
            utilizationRate, slope1, slope2, baseInterestRate, optimalUtilizationRate, reserveFactor
        );
        uint256 growth = RAY + (rate * timeElapsed) / YEAR_IN_SECONDS;
        return (currentLiquidityIndex * growth) / RAY;
    }
}
