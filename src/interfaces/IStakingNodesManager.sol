// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {RewardsType} from "src/interfaces/IRewardsDistributor.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";

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
    function isStakingNodesDelegator(address _address) external view returns (bool);
    function processRewards(uint nodeId, RewardsType rewardsType) external payable;
    function registerValidators(
        ValidatorData[] calldata _depositData
    ) external;
    function nodesLength() external view returns (uint);

    function upgradeableBeacon() external returns (UpgradeableBeacon);
}


