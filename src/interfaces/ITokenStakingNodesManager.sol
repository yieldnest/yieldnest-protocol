// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";

interface IRedemptionAssetsVaultExt is IRedemptionAssetsVault {
    function deposit(uint256 amount, address asset) external;
    function balances(address asset) external view returns (uint256 amount);
}

interface ITokenStakingNodesManager {

    struct WithdrawalAction {
        uint256 nodeId;
        uint256 amountToReinvest;
        uint256 amountToQueue;
        address asset;
    }

    function initializeV2(address _redemptionAssetsVault, address _withdrawer) external;

    function createTokenStakingNode() external returns (ITokenStakingNode);
    function registerTokenStakingNode(address _implementationContract) external;
    function upgradeTokenStakingNode(address _implementationContract) external;
    function setMaxNodeCount(uint256 _maxNodeCount) external;
    function hasTokenStakingNodeOperatorRole(address account) external view returns (bool);
    function hasTokenStakingNodeDelegatorRole(address account) external view returns (bool);

    function delegationManager() external view returns (IDelegationManager);
    function strategyManager() external view returns (IStrategyManager);
    function upgradeableBeacon() external view returns (UpgradeableBeacon);

    function getAllNodes() external view returns (ITokenStakingNode[] memory);
    function nodesLength() external view returns (uint256);
    function hasYieldNestStrategyManagerRole(address) external view returns (bool);
    function isStakingNodesWithdrawer(address _address) external view returns (bool);

    function getNodeById(uint256 nodeId) external view returns (ITokenStakingNode);
    function redemptionAssetsVault() external view returns (IRedemptionAssetsVaultExt);
}
