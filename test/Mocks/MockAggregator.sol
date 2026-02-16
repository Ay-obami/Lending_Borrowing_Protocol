// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @dev Minimal Chainlink Aggregator mock for local tests
contract MockAggregator is AggregatorV3Interface {
    int256 private answer;
    uint8 private _decimals;
    uint80 private roundId;

    constructor(int256 _answer, uint8 decimals_) {
        answer = _answer;
        _decimals = decimals_;
        roundId = 1;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, block.timestamp, block.timestamp, roundId);
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, block.timestamp, block.timestamp, roundId);
    }

    // helper to update mock price in tests
    function setAnswer(int256 _answer) external {
        answer = _answer;
        roundId++;
    }
}
