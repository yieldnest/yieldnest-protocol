pragma solidity ^0.8.0;

import "./IStakingNodesManager.sol";
import "./eigenlayer/IDelegationManager.sol";
import "./eigenlayer/IEigenPod.sol";

interface IStakingNode {

    /// @notice Configuration for contract initialization.
    struct Init {
        IStakingNodesManager stakingNodesManager;
    }

    function stakingNodesManager() external view returns (IStakingNodesManager);
    function eigenPod() external view returns (IEigenPod);
    function initialize(Init memory init) external;
    function createEigenPod() external returns (IEigenPod);
    function implementation() external view returns (address);
}
