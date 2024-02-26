// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynETH} from "./interfaces/IynETH.sol";
import {IStakingNodesManager,IStakingNode} from "./interfaces/IStakingNodesManager.sol";

contract ynViewer {
    IynETH public ynETH;
    IStakingNodesManager public stakingNodesManager;

    constructor(IynETH _ynETH, IStakingNodesManager _stakingNodesManager) {
        ynETH = _ynETH;
        stakingNodesManager = _stakingNodesManager;
    }

    function getAllValidators() public view returns (bytes[] memory) {
        return stakingNodesManager.getAllValidators();
    }

    function getAllStakingNodes() public view returns (IStakingNode[] memory) {
        return stakingNodesManager.getAllNodes();
    }
}
