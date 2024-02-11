pragma solidity ^0.8.0;

import "./eigenlayer-init-mainnet/IDelegationManager.sol";
import "./eigenlayer-init-mainnet/IEigenPodManager.sol";
import "./eigenlayer-init-mainnet/IDelayedWithdrawalRouter.sol";
import "./IStakingNode.sol";



interface IStakingNodesManager {

    struct DepositData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
        uint nodeId;
    }

    function eigenPodManager() external view returns (IEigenPodManager);

    function delegationManager() external view returns (IDelegationManager);

    function delayedWithdrawalRouter() external view returns (IDelayedWithdrawalRouter);

    function getAllValidators() external view returns (bytes[] memory);

    function getAllNodes() external view returns (IStakingNode[] memory);

    function isStakingNodesAdmin(address) external view returns (bool);

    function processWithdrawnETH(uint nodeId) external payable;

    function registerValidators(
        bytes32 _depositRoot,
        DepositData[] calldata _depositData
    ) external;
}


