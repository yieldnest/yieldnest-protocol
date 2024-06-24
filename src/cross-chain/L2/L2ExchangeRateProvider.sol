// SPDX-License-Identifier: LZBL-1.2
pragma solidity ^0.8.20;

import {L2ExchangeRateProviderUpgradeable} from "@layerzero/contracts/L2/L2ExchangeRateProviderUpgradeable.sol";
import {IAggregatorV3} from "@layerzero/contracts/interfaces/IAggregatorV3.sol";

contract L2ExchangeRateProvider is L2ExchangeRateProviderUpgradeable {
    error L2ExchangeRateProvider__InvalidRate();

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    /**
     * @dev Internal function to get rate and last updated time from a rate oracle
     * @param rateOracle Rate oracle contract
     * @return rate The exchange rate in 1e18 precision
     * @return lastUpdated Last updated time
     */
    function _getRateAndLastUpdated(address rateOracle, address)
        internal
        view
        override
        returns (uint256 rate, uint256 lastUpdated)
    {
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(rateOracle).latestRoundData();

        if (answer <= 0) revert L2ExchangeRateProvider__InvalidRate();

        return (uint256(answer), updatedAt);
    }
}