pragma solidity ^0.8.0;

interface IStakingNode {
    function stakingNodesManager() external view returns (address);
    function eigenPod() external view returns (address);
    function initialize(address _stakingNodesManager) external;
    function createEigenPod() external;
    function implementation() external view returns (address);
}
