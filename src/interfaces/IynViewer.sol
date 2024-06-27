// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNode, IStakingNodesManager} from "./IStakingNodesManager.sol";

interface IynViewer {

    struct StakingNodeData {
        uint256 nodeId;
        uint256 ethBalance;
        uint256 eigenPodEthBalance;
        uint256 podOwnerShares;
        address stakingNode;
        address eigenPod;
        address delegatedTo;
    }

    /// @notice Retrieves all validators' information.
    /// @return An array of bytes representing the validators' information.
    function getAllValidators() external view returns (IStakingNodesManager.Validator[] memory);

    /// @notice Retrieves the rate of ynETH in ETH.
    function getRate() external view returns (uint256);

    /// @notice Retrieves the withdrawal delay blocks for a given strategy.
    /// @param _strategy The address of the strategy.
    /// @return The withdrawal delay in blocks.
    function withdrawalDelayBlocks(address _strategy) external view returns (uint256);

    /// @notice Retrieves all staking nodes' information.
    function getStakingNodeData() external returns (StakingNodeData[] memory _data);
}