// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./IRewardsReceiver.sol";

interface IRewardsDistributor {
    function processRewards() external;

    /// @notice Returns the address of the execution layer rewards receiver.
    /// @return The address of the execution layer rewards receiver.
    function executionLayerReceiver() external view returns (IRewardsReceiver);

    /// @notice Returns the address of the consensus layer rewards receiver.
    /// @return The address of the consensus layer rewards receiver.
    function consensusLayerReceiver() external view returns (IRewardsReceiver);
}

