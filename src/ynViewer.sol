pragma solidity ^0.8.0;

import "./interfaces/IynETH.sol";
import "./interfaces/IStakingNodesManager.sol";

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
