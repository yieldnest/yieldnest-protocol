pragma solidity ^0.8.0;

import "./IStakingNodesManager.sol";
import "./eigenlayer-init-mainnet/IDelegationManager.sol";
import "./eigenlayer-init-mainnet/IEigenPod.sol";
import "./eigenlayer-init-mainnet/IStrategyManager.sol";


struct WithdrawalCompletionParams {
    uint256 middlewareTimesIndex;
    uint amount;
    uint32 withdrawalStartBlock;
    address delegatedAddress;
    uint96 nonce;
}

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
    function delegate(address operator) external;
    function withdrawBeforeRestaking() external;
    function claimDelayedWithdrawals(uint256 maxNumWithdrawals) external;

    
    function implementation() external view returns (address);

    function allocateStakedETH(uint amount) external payable;   
    function getETHBalance() external view returns (uint);
    function nodeId() external view returns (uint);

    function startWithdrawal(
        uint256 amount
    ) external returns (bytes32);

    function completeWithdrawal(
        WithdrawalCompletionParams memory withdrawalCompletionParams
    ) external;

    /// @notice Returns the beaconChainETHStrategy address used by the StakingNode.
    function beaconChainETHStrategy() external view returns (IStrategy);

}
