// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNode} from "./IStakingNode.sol";
import {IStakingNodesManager} from "./IStakingNodesManager.sol";



interface IynViewer {
    /// @notice Retrieves all validators' information.
    /// @return An array of bytes representing the validators' information.
    function getAllValidators() external view returns (IStakingNodesManager.Validator[] memory);

    /// @notice Retrieves all staking nodes in the system.
    /// @return An array of `IStakingNode` contracts representing the staking nodes.
    function getAllStakingNodes() external view returns (IStakingNode[] memory);
}