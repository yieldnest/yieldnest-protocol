pragma solidity ^0.8.0;

import "./interfaces/IynETH.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/IOracle.sol";

contract ynViewer {
    IynETH public ynETH;
    IStakingNodesManager public stakingNodesManager;
    IOracle public oracle;

    constructor(IynETH _ynETH, IStakingNodesManager _stakingNodesManager, IOracle _oracle) {
        ynETH = _ynETH;
        stakingNodesManager = _stakingNodesManager;
        oracle = _oracle;
    }

    function getAllValidators() public view returns (bytes[] memory) {
        return stakingNodesManager.getAllValidators();
    }
}
