pragma solidity ^0.8.0;

interface IStakingNodesManager {
    function createStakingNode(bool _createEigenPod) external returns (address);
    function eigenPodManager() external view returns (address);
}


