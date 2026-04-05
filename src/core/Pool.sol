// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {InterestCalculator} from "./InterestCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceFeeds} from "./PriceFeeds.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct ReserveData {
        uint256 totalDeposits;
        uint256 totalBorrows;
        uint256 supplyLiquidityIndex;
        uint256 borrowLiquidityIndex;
        uint256 lastUpdateTimestamp;
        uint256 liquidationThreshold;
        uint256 ltv;
        uint256 slope1;
        uint256 slope2;
        uint256 baseInterestRate;
        uint256 optimalUtilization;
        uint256 liquidationBonus; // Percentage
        uint256 reserveFactor;
        uint256 borrowCap;
        uint256 supplyCap;
        address priceFeed;
        address tokenAddress;
        bool isActive;
        bool isBorrowable;
        string reserveName;
    }

    struct Position {
        string collateralAsset;
        address collateralAssetPriceFeed;
        string borrowAsset;
        address borrowAssetPriceFeed;
        uint256 scaledDebt;
        uint256 collateralLocked;
        uint256 bufferPercent;
    }

    mapping(string => ReserveData) public reserves;
    mapping(address => mapping(string => uint256)) userScaledDeposits;
    mapping(address => mapping(string => uint256)) userScaledBorrows;
    mapping(address => mapping(string => uint256)) userLockedCollateral;
    mapping(address => mapping(uint256 => Position)) userPositions;
    mapping(address => uint256) userPositionCount;

    uint256 constant RAY = 1e18;
    uint256 constant MIN_BUFFER = 0.05e18; // 5%
    uint256 constant MAX_BUFFER = 1e18; // 100%
    uint256 constant MAX_UTILIZATION = 0.95e18; // 95%

    InterestCalculator public borrowInterestCalculator;
    InterestCalculator public supplyInterestCalculator;

    constructor() Ownable(msg.sender) {
        supplyInterestCalculator = new InterestCalculator(true);
        borrowInterestCalculator = new InterestCalculator(false);
    }

    function instantiateNewReserveData(
        string memory reserveName,
        address priceFeed,
        address tokenAddress,
        uint256 liquidationThreshold,
        uint256 ltv,
        uint256 slope1,
        uint256 slope2,
        uint256 baseInterestRate,
        uint256 optimalUtilization,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        uint256 borrowCap,
        uint256 supplyCap,
        bool isActive,
        bool isBorrowable
    ) public onlyOwner {
        require(reserves[reserveName].priceFeed == address(0), "Reserve already exists");
        require(optimalUtilization > 0, "Optimal utilization cannot be zero");
        require(optimalUtilization < RAY, "Optimal utilization cannot exceed 100%");
        require(reserveFactor < RAY, "Reserve factor cannot exceed 100%");
        require(baseInterestRate < RAY, "Base rate cannot exceed 100%");

        reserves[reserveName] = ReserveData({
            totalDeposits: 0,
            totalBorrows: 0,
            supplyLiquidityIndex: RAY,
            borrowLiquidityIndex: RAY,
            lastUpdateTimestamp: block.timestamp,
            liquidationThreshold: liquidationThreshold,
            ltv: ltv,
            slope1: slope1,
            slope2: slope2,
            baseInterestRate: baseInterestRate,
            optimalUtilization: optimalUtilization,
            liquidationBonus: liquidationBonus,
            reserveFactor: reserveFactor,
            borrowCap: borrowCap,
            supplyCap: supplyCap,
            priceFeed: priceFeed,
            tokenAddress: tokenAddress,
            isActive: isActive,
            isBorrowable: isBorrowable,
            reserveName: reserveName
        });
    }

    function deposit(string memory reserveName, uint256 amount) public nonReentrant {
        ReserveData storage reserveData = reserves[reserveName];
        require(reserveData.isActive, "Reserve not active");
        require(reserveData.totalDeposits + amount <= reserveData.supplyCap, "Supply cap exceeded");

        _updateLiquidityIndexes(reserveData);

        IERC20(reserveData.tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        reserveData.totalDeposits += amount;

        uint256 scaledAmount = (amount * RAY) / reserveData.supplyLiquidityIndex;
        userScaledDeposits[msg.sender][reserveName] += scaledAmount;
    }

    function withdraw(string memory reserveName, uint256 amount) public nonReentrant {
        ReserveData storage reserveData = reserves[reserveName];

        _updateLiquidityIndexes(reserveData);

        uint256 scaledAmount = (amount * RAY) * reserveData.supplyLiquidityIndex;

        uint256 availableLiquidity = reserveData.totalDeposits - reserveData.totalBorrows;
        require(amount <= availableLiquidity, "Insufficient pool liquidity");

        require(userScaledDeposits[msg.sender][reserveName] >= scaledAmount, "Insufficient user balance");
        userScaledDeposits[msg.sender][reserveName] -= scaledAmount;

        IERC20(reserveData.tokenAddress).safeTransfer(msg.sender, amount);

        userScaledDeposits[msg.sender][reserveName] -= scaledAmount;
        reserveData.totalDeposits -= amount;
    }

    function borrow(string memory collateralName, string memory borrowName, uint256 amount, uint256 bufferPercent)
        public
        nonReentrant
    {
        _borrow(reserves[collateralName], reserves[borrowName], amount, bufferPercent);
    }

    function repay(string memory collateralName, string memory borrowName, uint256 positionId, uint256 repayAmount)
        public
        nonReentrant
    {
        _repay(reserves[collateralName], reserves[borrowName], positionId, repayAmount);
    }

    function getUserDepositBalance(string memory reserveName, address user) public view returns (uint256) {
        ReserveData storage reserveData = reserves[reserveName];
        return (userScaledDeposits[user][reserveName] * reserveData.supplyLiquidityIndex) / RAY;
    }

    function getUserBorrowBalance(string memory reserveName, address user) public view returns (uint256) {
        ReserveData storage reserveData = reserves[reserveName];
        return (userScaledBorrows[user][reserveName] * reserveData.borrowLiquidityIndex) / RAY;
    }

    function getUtilizationRate(string memory reserveName) public view returns (uint256) {
        ReserveData storage assetData = reserves[reserveName];
        if (assetData.totalDeposits == 0) return 0;
        return (assetData.totalBorrows * RAY) / assetData.totalDeposits;
    }

    function _updateLiquidityIndexes(ReserveData storage reserveData) internal {
        uint256 timeElapsed = block.timestamp - reserveData.lastUpdateTimestamp;
        if (timeElapsed == 0) return;

        uint256 utilizationRate =
            reserveData.totalDeposits == 0 ? 0 : (reserveData.totalBorrows * RAY) / reserveData.totalDeposits;

        reserveData.supplyLiquidityIndex = supplyInterestCalculator.computeUpdatedLiquidityIndex(
            reserveData.supplyLiquidityIndex,
            utilizationRate,
            timeElapsed,
            reserveData.slope1,
            reserveData.slope2,
            reserveData.baseInterestRate,
            reserveData.optimalUtilization,
            reserveData.reserveFactor
        );

        reserveData.borrowLiquidityIndex = borrowInterestCalculator.computeUpdatedLiquidityIndex(
            reserveData.borrowLiquidityIndex,
            utilizationRate,
            timeElapsed,
            reserveData.slope1,
            reserveData.slope2,
            reserveData.baseInterestRate,
            reserveData.optimalUtilization,
            reserveData.reserveFactor
        );

        reserveData.lastUpdateTimestamp = block.timestamp;
    }

    function _borrow(
        ReserveData storage collateralData,
        ReserveData storage assetTobeBorrowedData,
        uint256 amount,
        uint256 bufferPercent
    ) internal {
        _updateLiquidityIndexes(collateralData);
        _updateLiquidityIndexes(assetTobeBorrowedData);

        // Checks
        require(assetTobeBorrowedData.isBorrowable, "Asset not borrowable");
        require(bufferPercent >= MIN_BUFFER, "Buffer too low");
        require(bufferPercent <= MAX_BUFFER, "Buffer too high");
        require(amount + assetTobeBorrowedData.totalBorrows <= assetTobeBorrowedData.borrowCap, "Borrow cap exceeded");
        require(
            ((amount + assetTobeBorrowedData.totalBorrows) * RAY) / assetTobeBorrowedData.totalDeposits
                < MAX_UTILIZATION,
            "Liquidity ratio too low"
        );

        uint256 borrowAmountInUsd = (getPrice(assetTobeBorrowedData.priceFeed) * amount) / RAY;
        uint256 minimumCollateralInUsd = (borrowAmountInUsd * RAY) / collateralData.ltv;
        uint256 collateralToLockInUsd = (minimumCollateralInUsd * (RAY + bufferPercent)) / RAY;
        uint256 collateralToLock = (collateralToLockInUsd * RAY) / getPrice(collateralData.priceFeed);

        uint256 actualDeposits =
            (userScaledDeposits[msg.sender][collateralData.reserveName] * collateralData.supplyLiquidityIndex) / RAY;
        require(actualDeposits >= collateralToLock, "Insufficient free collateral");

        uint256 remaining = actualDeposits - collateralToLock;
        userScaledDeposits[msg.sender][collateralData.reserveName] =
            (remaining * RAY) / collateralData.supplyLiquidityIndex;

        uint256 scaledAmount = (amount * RAY) / assetTobeBorrowedData.borrowLiquidityIndex;

        uint256 positionId = userPositionCount[msg.sender];
        userPositions[msg.sender][positionId] = Position({
            collateralAsset: collateralData.reserveName,
            collateralAssetPriceFeed: collateralData.priceFeed,
            borrowAsset: assetTobeBorrowedData.reserveName,
            borrowAssetPriceFeed: assetTobeBorrowedData.priceFeed,
            scaledDebt: scaledAmount,
            collateralLocked: collateralToLock,
            bufferPercent: bufferPercent
        });
        userPositionCount[msg.sender]++;

        assetTobeBorrowedData.totalBorrows += amount;

        userLockedCollateral[msg.sender][collateralData.reserveName] += collateralToLock;

        userScaledBorrows[msg.sender][assetTobeBorrowedData.reserveName] += scaledAmount;
    }

    function _repay(
        ReserveData storage collateralData,
        ReserveData storage assetTobeBorrowedData,
        uint256 positionId,
        uint256 repayAmount
    ) internal {
        _updateLiquidityIndexes(collateralData);
        _updateLiquidityIndexes(assetTobeBorrowedData);

        Position storage position = userPositions[msg.sender][positionId];

        require(
            keccak256(bytes(position.borrowAsset)) == keccak256(bytes(assetTobeBorrowedData.reserveName)),
            "Wrong borrow asset"
        );
        require(
            keccak256(bytes(position.collateralAsset)) == keccak256(bytes(collateralData.reserveName)),
            "Wrong collateral asset"
        );
        require(position.scaledDebt > 0, "No debt on position");

        uint256 currentDebt = (position.scaledDebt * assetTobeBorrowedData.borrowLiquidityIndex) / RAY;
        require(repayAmount <= currentDebt, "Repay exceeds debt");

        uint256 scaledRepay = (repayAmount * RAY) / assetTobeBorrowedData.borrowLiquidityIndex;

        uint256 collateralToRelease = (position.collateralLocked * repayAmount) / currentDebt;

        position.scaledDebt -= scaledRepay;
        position.collateralLocked -= collateralToRelease;

        assetTobeBorrowedData.totalBorrows -= repayAmount;

        uint256 actualDeposits =
            (userScaledDeposits[msg.sender][collateralData.reserveName] * collateralData.supplyLiquidityIndex) / RAY;
        uint256 newTotal = actualDeposits + collateralToRelease;
        userScaledDeposits[msg.sender][collateralData.reserveName] =
            (newTotal * RAY) / collateralData.supplyLiquidityIndex;

        userLockedCollateral[msg.sender][collateralData.reserveName] -= collateralToRelease;

        userScaledBorrows[msg.sender][assetTobeBorrowedData.reserveName] -= scaledRepay;

        if (position.scaledDebt == 0) {
            delete userPositions[msg.sender][positionId];
        }
    }

    function liquidatePosition(address user, uint256 positionId) internal {
        require(!checkPositionHealth(user, positionId), "Position is healthy");

        Position storage position = userPositions[user][positionId];
        ReserveData storage collateralData = reserves[position.collateralAsset];
        ReserveData storage borrowData = reserves[position.borrowAsset];

        _updateLiquidityIndexes(collateralData);
        _updateLiquidityIndexes(borrowData);

        uint256 rawCollateral = position.collateralLocked;
        uint256 rawDebt = (position.scaledDebt * borrowData.borrowLiquidityIndex) / RAY;

        IERC20(borrowData.tokenAddress).safeTransferFrom(msg.sender, address(this), rawDebt);

        uint256 collateralToSeize = rawCollateral;

        borrowData.totalBorrows -= rawDebt;
        userScaledBorrows[user][position.borrowAsset] -= position.scaledDebt;
        userLockedCollateral[user][position.collateralAsset] -= rawCollateral;

        delete userPositions[user][positionId];

        IERC20(collateralData.tokenAddress).safeTransfer(msg.sender, collateralToSeize);
    }

    function getHealthFactor(Position storage position) internal view returns (uint256) {
        ReserveData storage collateralData = reserves[position.collateralAsset];
        ReserveData storage borrowData = reserves[position.borrowAsset];

        uint256 collateralValue = (position.collateralLocked * getPrice(position.collateralAssetPriceFeed)) / RAY;
        uint256 adjustedCollateral = (collateralValue * collateralData.liquidationThreshold) / RAY;

        uint256 rawDebt = (position.scaledDebt * borrowData.borrowLiquidityIndex) / RAY;
        uint256 debtValue = (rawDebt * getPrice(position.borrowAssetPriceFeed)) / RAY;

        if (debtValue == 0) return type(uint256).max;
        return (adjustedCollateral * RAY) / debtValue;
    }

    function checkPositionHealth(address user, uint256 positionId) public view returns (bool) {
        Position storage position = userPositions[user][positionId];
        require(position.scaledDebt > 0, "No active position");
        return getHealthFactor(position) >= RAY;
    }

    function getUserPositions(address user) public view returns (Position[] memory) {
        uint256 positionCount = userPositionCount[user];
        Position[] memory positions = new Position[](positionCount);
        for (uint256 i = 0; i < positionCount; i++) {
            positions[i] = userPositions[user][i];
        }
        return positions;
    }

    function getPrice(address tokenPriceFeedAddress) internal view returns (uint256) {
        int256 price = PriceFeeds(tokenPriceFeedAddress).getLatestPrice();
        return uint256(price);
    }
}
