/// SPDX-License-Identifier: BSD 3-Clause License

pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "src/external/chainlink/AggregatorV3Interface.sol";

contract MockAggregatorV3 is AggregatorV3Interface {

    // implement a mock aggregator
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Implement your mock logic here
        roundId = _roundId;
        answer = 1.01 ether;
        startedAt = block.timestamp - 3600;
        updatedAt = block.timestamp - 1800;
        answeredInRound = 1;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Implement your mock logic here
        roundId = 1;
        answer = 1.01 ether;
        startedAt = block.timestamp - 3600;
        updatedAt = block.timestamp - 1800;
        answeredInRound = 1;
    }
}