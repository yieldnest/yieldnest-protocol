// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelayedWithdrawalRouter} from "../external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {IDelegationManager} from "../external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "../external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";

import {IEigenPodManager} from "../external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "./IStakingNode.sol";

interface IStakingNodesManager {

    struct ValidatorData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
        uint nodeId;
    }

    struct Validator {
        bytes publicKey;
        uint nodeId;
    }

    function eigenPodManager() external view returns (IEigenPodManager);
    function delegationManager() external view returns (IDelegationManager);
    function strategyManager() external view returns (IStrategyManager);

    function delayedWithdrawalRouter() external view returns (IDelayedWithdrawalRouter);
    function getAllValidators() external view returns (Validator[] memory);
    function getAllNodes() external view returns (IStakingNode[] memory);
    function isStakingNodesAdmin(address) external view returns (bool);
    function processWithdrawnETH(uint nodeId, uint withdrawnValidatorPrincipal) external payable;
    function registerValidators(
        bytes32 _depositRoot,
        ValidatorData[] calldata _depositData
    ) external;
    function nodesLength() external view returns (uint);

    function upgradeableBeacon() external returns (UpgradeableBeacon);
}


