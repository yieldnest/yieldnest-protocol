// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IDelayedWithdrawalRouter} from "../external/eigenlayer/v1/interfaces/IDelayedWithdrawalRouter.sol";
import {IDelegationManager} from "../external/eigenlayer/v1/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "../external/eigenlayer/v1/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "./IStakingNode.sol";

interface IStakingNodesManager {

    struct ValidatorData {
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
    function processWithdrawnETH(uint nodeId, uint withdrawnValidatorPrincipal) external payable;
    function registerValidators(
        bytes32 _depositRoot,
        ValidatorData[] calldata _depositData
    ) external;
}


