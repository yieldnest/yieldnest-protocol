// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynETH} from "./interfaces/IynETH.sol";
import {IynViewer} from "./interfaces/IynViewer.sol";
import {IStakingNodesManager,IStakingNode} from "./interfaces/IStakingNodesManager.sol";

contract ynViewer is IynViewer {
    IynETH public ynETH;
    IStakingNodesManager public stakingNodesManager;

    /// @notice Initializes a new ynViewer contract.
    /// @param _ynETH The address of the ynETH contract.
    /// @param _stakingNodesManager The address of the StakingNodesManager contract.
    constructor(IynETH _ynETH, IStakingNodesManager _stakingNodesManager) {
        ynETH = _ynETH;
        stakingNodesManager = _stakingNodesManager;
    }

    /// @inheritdoc IynViewer
    function getAllValidators() public view returns (IStakingNodesManager.Validator[] memory) {
        return stakingNodesManager.getAllValidators();
    }

    /// @inheritdoc IynViewer
    function getAllStakingNodes() public view returns (IStakingNode[] memory) {
        return stakingNodesManager.getAllNodes();
    }
}
