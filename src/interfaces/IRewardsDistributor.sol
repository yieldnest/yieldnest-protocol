// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IRewardsReceiver} from "./IRewardsReceiver.sol";

interface IRewardsDistributor {

    /// @notice Returns the address of the ynETH token.
    /// @return address of the ynETH token.
    function ynETH() external view returns (address);

    /// @notice Processes the rewards for the execution and consensus layer.
    /// @dev This function should be called by off-chain rewards distribution service.
    function processRewards() external;

    /// @notice Returns the address of the execution layer rewards receiver.
    /// @return address of the execution layer rewards receiver.
    function executionLayerReceiver() external view returns (IRewardsReceiver);

    /// @notice Returns the address of the consensus layer rewards receiver.
    /// @return address of the consensus layer rewards receiver.
    function consensusLayerReceiver() external view returns (IRewardsReceiver);

    /// @notice Returns the address of the fees receiver.
    /// @return address of the fees receiver.
    function feesReceiver() external view returns (address);

    /// @notice Returns the protocol fees in basis points (1/10000).
    /// @return uint16 fees in basis points.
    function feesBasisPoints() external view returns (uint16);

    /// @notice Sets the address to receive protocol fees.
    /// @param newReceiver The new fees receiver address.
    function setFeesReceiver(address payable newReceiver) external;

    /// @notice Sets the protocol fees in basis points (1/10000).
    /// @param newFeesBasisPoints The new fees in basis points.
    function setFeesBasisPoints(uint16 newFeesBasisPoints) external;
}

