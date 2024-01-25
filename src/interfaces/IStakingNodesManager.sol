pragma solidity ^0.8.0;

import "./eigenlayer/IDelegationManager.sol";
import "./eigenlayer/IEigenPodManager.sol";
import "./eigenlayer/IDelayedWithdrawalRouter.sol";


interface IStakingNodesManager {

    struct DepositData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
    }

    function eigenPodManager() external view returns (IEigenPodManager);

    function delegationManager() external view returns (IDelegationManager);

    function delayedWithdrawalRouter() external view returns (IDelayedWithdrawalRouter);

    function getAllValidators() external view returns (bytes[] memory);

    function isStakingNodesAdmin(address) external view returns (bool);

    function processWithdrawnETH(uint nodeId) external payable;

    function registerValidators(
        bytes32 _depositRoot,
        DepositData[] calldata _depositData
    ) external;
}


