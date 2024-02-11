pragma solidity ^0.8.0;

import "./IStakingNodesManager.sol";
import "./eigenlayer-init-mainnet/IDelegationManager.sol";
import "./eigenlayer-init-mainnet/IEigenPod.sol";
import "./eigenlayer-init-mainnet/IStrategyManager.sol";

interface IStakingNode {

    /// @notice Configuration for contract initialization.
    struct Init {
        IStakingNodesManager stakingNodesManager;
        IStrategyManager strategyManager;
        uint nodeId;
    }

    function stakingNodesManager() external view returns (IStakingNodesManager);
    function eigenPod() external view returns (IEigenPod);
    function initialize(Init memory init) external;
    function createEigenPod() external returns (IEigenPod);
    function implementation() external view returns (address);

    function allocateStakedETH(uint amount) external payable;   
    function getETHBalance() external view returns (uint);

}
