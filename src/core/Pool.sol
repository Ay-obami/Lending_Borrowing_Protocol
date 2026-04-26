// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {InterestCalculator} from "./InterestCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceFeeds} from "test/Mocks/MockAggregator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ================================================================
    // Errors
    // ================================================================

    error ReserveAlreadyExists(string reserveName);
    error ReserveDoesNotExist(string reserveName);
    error ReserveNotActive(string reserveName);
    error OptimalUtilizationCannotBeZero();
    error OptimalUtilizationExceeds100();
    error ReserveFactorExceeds100();
    error BaseRateExceeds100();
    error SupplyCapExceeded(string reserveName, uint256 supplyCap);
    error BorrowCapExceeded(string reserveName, uint256 borrowCap);
    error MaxUtilizationExceeded(string reserveName);
    error AssetNotBorrowable(string reserveName);
    error BufferTooLow(uint256 provided, uint256 minimum);
    error BufferTooHigh(uint256 provided, uint256 maximum);
    error InsufficientFreeCollateral(uint256 available, uint256 required);
    error InsufficientPoolLiquidity(uint256 available, uint256 requested);
    error InsufficientUserBalance(uint256 available, uint256 requested);
    error WrongBorrowAsset(string expected, string provided);
    error WrongCollateralAsset(string expected, string provided);
    error NoDebtOnPosition(uint256 positionId);
    error NoActivePosition(uint256 positionId);
    error RepayExceedsDebt(uint256 debt, uint256 repayAmount);
    error PositionIsHealthy(address user, uint256 positionId);
    error InvalidPrice(address priceFeed);
    error ZeroAmount();
    error ZeroAddress();
    error InvalidLTV(uint256 ltv, uint256 liquidationThreshold);

    // ================================================================
    // Structs
    // ================================================================

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
        uint256 liquidationBonus;
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

    // ================================================================
    // State
    // ================================================================

    mapping(string => ReserveData) public reserves;
    mapping(address => mapping(string => uint256)) userScaledDeposits;
    mapping(address => mapping(string => uint256)) userScaledBorrows;
    mapping(address => mapping(string => uint256)) userLockedCollateral;
    mapping(address => mapping(uint256 => Position)) userPositions;
    mapping(address => uint256) userPositionCount;

    uint256 constant RAY = 1e18;
    uint256 constant MIN_BUFFER = 0.05e18;
    uint256 constant MAX_BUFFER = 1e18;
    uint256 constant MAX_UTILIZATION = 0.95e18;

    InterestCalculator public borrowInterestCalculator;
    InterestCalculator public supplyInterestCalculator;

    // ================================================================
    // Events
    // ================================================================

    event ReserveInitialized(
        string indexed reserveName,
        address indexed tokenAddress,
        address indexed priceFeed,
        uint256 ltv,
        uint256 liquidationThreshold
    );
    event ReserveStatusUpdated(string indexed reserveName, bool isActive);
    event ReserveBorrowStatusUpdated(string indexed reserveName, bool isBorrowable);
    event Deposit(address indexed user, string indexed reserveName, uint256 amount, uint256 scaledAmount);
    event Withdraw(address indexed user, string indexed reserveName, uint256 amount, uint256 scaledAmount);
    event Borrow(
        address indexed user,
        string indexed borrowAsset,
        string indexed collateralAsset,
        uint256 amount,
        uint256 collateralLocked,
        uint256 positionId
    );
    event Repay(
        address indexed user,
        string indexed borrowAsset,
        string indexed collateralAsset,
        uint256 repayAmount,
        uint256 collateralReleased,
        uint256 positionId
    );
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        string indexed collateralAsset,
        string borrowAsset,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 positionId
    );
    event LiquidityIndexUpdated(string indexed reserveName, uint256 supplyLiquidityIndex, uint256 borrowLiquidityIndex);

    // ================================================================
    // Modifiers
    // ================================================================

    modifier reserveExists(string memory reserveName) {
        _reserveExists(reserveName);
        _;
    }

    modifier reserveActive(string memory reserveName) {
        _reserveActive(reserveName);
        _;
    }

    modifier nonZeroAmount(uint256 amount) {
        _nonZeroAmount(amount);
        _;
    }

    modifier nonZeroAddress(address addr) {
        _nonZeroAddress(addr);
        _;
    }

    // ================================================================
    // Constructor
    // ================================================================

    constructor() Ownable(msg.sender) {
        supplyInterestCalculator = new InterestCalculator(true);
        borrowInterestCalculator = new InterestCalculator(false);
    }

    // ================================================================
    // Admin
    // ================================================================

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
    ) public onlyOwner nonZeroAddress(priceFeed) nonZeroAddress(tokenAddress) {
        if (reserves[reserveName].priceFeed != address(0)) revert ReserveAlreadyExists(reserveName);
        if (optimalUtilization == 0) revert OptimalUtilizationCannotBeZero();
        if (optimalUtilization >= RAY) revert OptimalUtilizationExceeds100();
        if (reserveFactor >= RAY) revert ReserveFactorExceeds100();
        if (baseInterestRate >= RAY) revert BaseRateExceeds100();
        if (ltv >= liquidationThreshold) revert InvalidLTV(ltv, liquidationThreshold);

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

        emit ReserveInitialized(reserveName, tokenAddress, priceFeed, ltv, liquidationThreshold);
    }

    function setReserveActive(string memory reserveName, bool active) external onlyOwner reserveExists(reserveName) {
        reserves[reserveName].isActive = active;
        emit ReserveStatusUpdated(reserveName, active);
    }

    function setReserveBorrowable(string memory reserveName, bool borrowable)
        external
        onlyOwner
        reserveExists(reserveName)
    {
        reserves[reserveName].isBorrowable = borrowable;
        emit ReserveBorrowStatusUpdated(reserveName, borrowable);
    }

    // ================================================================
    // Core
    // ================================================================

    function deposit(string memory reserveName, uint256 amount)
        public
        nonReentrant
        reserveExists(reserveName)
        reserveActive(reserveName)
        nonZeroAmount(amount)
    {
        ReserveData storage reserveData = reserves[reserveName];

        if (reserveData.totalDeposits + amount > reserveData.supplyCap) {
            revert SupplyCapExceeded(reserveName, reserveData.supplyCap);
        }

        _updateLiquidityIndexes(reserveData);

        IERC20(reserveData.tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        reserveData.totalDeposits += amount;

        uint256 scaledAmount = (amount * RAY) / reserveData.supplyLiquidityIndex;
        userScaledDeposits[msg.sender][reserveName] += scaledAmount;

        emit Deposit(msg.sender, reserveName, amount, scaledAmount);
    }

    function withdraw(string memory reserveName, uint256 amount)
        public
        nonReentrant
        reserveExists(reserveName)
        nonZeroAmount(amount)
    {
        ReserveData storage reserveData = reserves[reserveName];

        _updateLiquidityIndexes(reserveData);

        uint256 scaledAmount = (amount * RAY) / reserveData.supplyLiquidityIndex;

        uint256 availableLiquidity = reserveData.totalDeposits - reserveData.totalBorrows;
        if (amount > availableLiquidity) {
            revert InsufficientPoolLiquidity(availableLiquidity, amount);
        }
        if (userScaledDeposits[msg.sender][reserveName] < scaledAmount) {
            revert InsufficientUserBalance(userScaledDeposits[msg.sender][reserveName], scaledAmount);
        }

        userScaledDeposits[msg.sender][reserveName] -= scaledAmount;
        reserveData.totalDeposits -= amount;

        IERC20(reserveData.tokenAddress).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, reserveName, amount, scaledAmount);
    }

    function borrow(string memory collateralName, string memory borrowName, uint256 amount, uint256 bufferPercent)
        public
        nonReentrant
        reserveExists(collateralName)
        reserveExists(borrowName)
        reserveActive(collateralName)
        reserveActive(borrowName)
        nonZeroAmount(amount)
    {
        _borrow(reserves[collateralName], reserves[borrowName], amount, bufferPercent);
    }

    function repay(string memory collateralName, string memory borrowName, uint256 positionId, uint256 repayAmount)
        public
        nonReentrant
        reserveExists(collateralName)
        reserveExists(borrowName)
        nonZeroAmount(repayAmount)
    {
        _repay(reserves[collateralName], reserves[borrowName], positionId, repayAmount);
    }

    function liquidate(address user, uint256 positionId) public nonReentrant nonZeroAddress(user) {
        _liquidatePosition(user, positionId);
    }

    // ================================================================
    // Internal
    // ================================================================

    function _borrow(
        ReserveData storage collateralData,
        ReserveData storage assetTobeBorrowedData,
        uint256 amount,
        uint256 bufferPercent
    ) internal {
        _updateLiquidityIndexes(collateralData);
        _updateLiquidityIndexes(assetTobeBorrowedData);

        if (!assetTobeBorrowedData.isBorrowable) revert AssetNotBorrowable(assetTobeBorrowedData.reserveName);
        if (bufferPercent < MIN_BUFFER) revert BufferTooLow(bufferPercent, MIN_BUFFER);
        if (bufferPercent > MAX_BUFFER) revert BufferTooHigh(bufferPercent, MAX_BUFFER);
        if (amount + assetTobeBorrowedData.totalBorrows > assetTobeBorrowedData.borrowCap) {
            revert BorrowCapExceeded(assetTobeBorrowedData.reserveName, assetTobeBorrowedData.borrowCap);
        }
        if (
            ((amount + assetTobeBorrowedData.totalBorrows) * RAY) / assetTobeBorrowedData.totalDeposits
                >= MAX_UTILIZATION
        ) revert MaxUtilizationExceeded(assetTobeBorrowedData.reserveName);

        uint256 borrowAmountInUsd = (getPrice(assetTobeBorrowedData.priceFeed) * amount) / RAY;
        uint256 minimumCollateralInUsd = (borrowAmountInUsd * RAY) / collateralData.ltv;
        uint256 collateralToLockInUsd = (minimumCollateralInUsd * (RAY + bufferPercent)) / RAY;
        uint256 collateralToLock = (collateralToLockInUsd * RAY) / getPrice(collateralData.priceFeed);

        uint256 actualDeposits =
            (userScaledDeposits[msg.sender][collateralData.reserveName] * collateralData.supplyLiquidityIndex) / RAY;

        if (actualDeposits < collateralToLock) {
            revert InsufficientFreeCollateral(actualDeposits, collateralToLock);
        }

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

        emit Borrow(
            msg.sender,
            assetTobeBorrowedData.reserveName,
            collateralData.reserveName,
            amount,
            collateralToLock,
            positionId
        );
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

        if (keccak256(bytes(position.borrowAsset)) != keccak256(bytes(assetTobeBorrowedData.reserveName))) {
            revert WrongBorrowAsset(position.borrowAsset, assetTobeBorrowedData.reserveName);
        }
        if (keccak256(bytes(position.collateralAsset)) != keccak256(bytes(collateralData.reserveName))) {
            revert WrongCollateralAsset(position.collateralAsset, collateralData.reserveName);
        }
        if (position.scaledDebt == 0) revert NoDebtOnPosition(positionId);

        uint256 currentDebt = (position.scaledDebt * assetTobeBorrowedData.borrowLiquidityIndex) / RAY;
        if (repayAmount > currentDebt) revert RepayExceedsDebt(currentDebt, repayAmount);

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

        emit Repay(
            msg.sender,
            assetTobeBorrowedData.reserveName,
            collateralData.reserveName,
            repayAmount,
            collateralToRelease,
            positionId
        );

        if (position.scaledDebt == 0) {
            delete userPositions[msg.sender][positionId];
        }
    }

    function _liquidatePosition(address user, uint256 positionId) internal {
        if (checkPositionHealth(user, positionId)) revert PositionIsHealthy(user, positionId);

        Position storage position = userPositions[user][positionId];
        ReserveData storage collateralData = reserves[position.collateralAsset];
        ReserveData storage borrowData = reserves[position.borrowAsset];

        _updateLiquidityIndexes(collateralData);
        _updateLiquidityIndexes(borrowData);

        uint256 rawCollateral = position.collateralLocked;
        uint256 rawDebt = (position.scaledDebt * borrowData.borrowLiquidityIndex) / RAY;

        borrowData.totalBorrows -= rawDebt;
        userScaledBorrows[user][position.borrowAsset] -= position.scaledDebt;
        userLockedCollateral[user][position.collateralAsset] -= rawCollateral;

        string memory collateralAsset = position.collateralAsset;
        string memory borrowAsset = position.borrowAsset;

        delete userPositions[user][positionId];

        collateralData.totalDeposits -= rawCollateral;

        IERC20(borrowData.tokenAddress).safeTransferFrom(msg.sender, address(this), rawDebt);
        IERC20(collateralData.tokenAddress).safeTransfer(msg.sender, rawCollateral);

        emit Liquidated(user, msg.sender, collateralAsset, borrowAsset, rawDebt, rawCollateral, positionId);
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

        emit LiquidityIndexUpdated(
            reserveData.reserveName, reserveData.supplyLiquidityIndex, reserveData.borrowLiquidityIndex
        );
    }

    // ================================================================
    // Views
    // ================================================================

    function getUserDepositBalance(string memory reserveName, address user)
        public
        view
        reserveExists(reserveName)
        returns (uint256)
    {
        ReserveData storage reserveData = reserves[reserveName];
        return (userScaledDeposits[user][reserveName] * reserveData.supplyLiquidityIndex) / RAY;
    }

    function getUserBorrowBalance(string memory reserveName, address user)
        public
        reserveExists(reserveName)
        returns (uint256)
    {
        ReserveData storage reserveData = reserves[reserveName];
        _updateLiquidityIndexes(reserveData);
        return (userScaledBorrows[user][reserveName] * reserveData.borrowLiquidityIndex) / RAY;
    }

    function getUtilizationRate(string memory reserveName) public view reserveExists(reserveName) returns (uint256) {
        ReserveData storage assetData = reserves[reserveName];
        if (assetData.totalDeposits == 0) return 0;
        return (assetData.totalBorrows * RAY) / assetData.totalDeposits;
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
        if (position.scaledDebt == 0) revert NoActivePosition(positionId);
        return getHealthFactor(position) >= RAY;
    }

    function getUserPositions(address user) public view returns (Position[] memory) {
        uint256 count = userPositionCount[user];
        Position[] memory positions = new Position[](count);
        for (uint256 i = 0; i < count; i++) {
            positions[i] = userPositions[user][i];
        }
        return positions;
    }

    function getPrice(address priceFeed) internal view returns (uint256) {
        (, int256 price,,,) = PriceFeeds(priceFeed).latestRoundData();
        if (price <= 0) revert InvalidPrice(priceFeed);
        return uint256(price);
    }

    function getReserveData(string memory reserveName)
        public
        view
        reserveExists(reserveName)
        returns (ReserveData memory)
    {
        return reserves[reserveName];
    }

    function _reserveExists(string memory reserveName) internal view {
        if (reserves[reserveName].priceFeed == address(0)) {
            revert ReserveDoesNotExist(reserveName);
        }
    }

    function _reserveActive(string memory reserveName) internal view {
        if (!reserves[reserveName].isActive) {
            revert ReserveNotActive(reserveName);
        }
    }

    function _nonZeroAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert ZeroAmount();
        }
    }

    function _nonZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }
}
