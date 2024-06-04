// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

// --------------------------------------------------------------------------------------
// $$\     $$\ $$\           $$\       $$\ $$\   $$\                       $$\     
// \$$\   $$  |\__|          $$ |      $$ |$$$\  $$ |                      $$ |    
//  \$$\ $$  / $$\  $$$$$$\  $$ | $$$$$$$ |$$$$\ $$ | $$$$$$\   $$$$$$$\ $$$$$$\   
//   \$$$$  /  $$ |$$  __$$\ $$ |$$  __$$ |$$ $$\$$ |$$  __$$\ $$  _____|\_$$  _|  
//    \$$  /   $$ |$$$$$$$$ |$$ |$$ /  $$ |$$ \$$$$ |$$$$$$$$ |\$$$$$$\    $$ |    
//     $$ |    $$ |$$   ____|$$ |$$ |  $$ |$$ |\$$$ |$$   ____| \____$$\   $$ |$$\ 
//     $$ |    $$ |\$$$$$$$\ $$ |\$$$$$$$ |$$ | \$$ |\$$$$$$$\ $$$$$$$  |  \$$$$  |
//     \__|    \__| \_______|\__| \_______|\__|  \__| \_______|\_______/    \____/ 
//--------------------------------------------------------------------------------------
//----------------------------------  IynViewer  ---------------------------------------
//--------------------------------------------------------------------------------------

import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";



interface IynViewer {
    /// @notice Retrieves all validators' information.
    /// @return An array of bytes representing the validators' information.
    function getAllValidators() external view returns (IStakingNodesManager.Validator[] memory);

    /// @notice Retrieves all staking nodes in the system.
    /// @return An array of `IStakingNode` contracts representing the staking nodes.
    function getAllStakingNodes() external view returns (IStakingNode[] memory);
}