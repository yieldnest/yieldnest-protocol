// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {RewardsType} from "src/interfaces/IRewardsDistributor.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";


interface IStakingNodesManager {

    struct ValidatorData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
        uint256 nodeId;
    }

    struct Validator {
        bytes publicKey;
        uint256 nodeId;
    }

    struct WithdrawalAction {
        uint256 nodeId;
        uint256 amountToReinvest;
        uint256 amountToQueue;
        uint256 rewardsAmount;
    }

    function eigenPodManager() external view returns (IEigenPodManager);
    function delegationManager() external view returns (IDelegationManager);
    function strategyManager() external view returns (IStrategyManager);
    function rewardsCoordinator()  external view returns (IRewardsCoordinator);

    function getAllValidators() external view returns (Validator[] memory);
    function getAllNodes() external view returns (IStakingNode[] memory);
    function isStakingNodesOperator(address) external view returns (bool);
    function isStakingNodesDelegator(address _address) external view returns (bool);
    function processRewards(uint256 nodeId, RewardsType rewardsType) external payable;
    function registerValidators(
        ValidatorData[] calldata _depositData
    ) external;
    function nodesLength() external view returns (uint256);

    function upgradeableBeacon() external returns (UpgradeableBeacon);

    function totalDeposited() external view returns (uint256);

    function processPrincipalWithdrawals(
        WithdrawalAction[] memory actions
    ) external;

    function redemptionAssetsVault() external returns (IRedemptionAssetsVault);

    function isStakingNodesWithdrawer(address _address) external view returns (bool);

    function nodes(uint256 index) external view returns (IStakingNode);
}
