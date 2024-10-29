// SPDX-License-Identifier: BSD-3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";
import {YnEigenInit, YnEigenImplementations} from "./YnEigenStructs.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

struct YnEigenActors {
    address ADMIN;
    address PAUSE_ADMIN;
    address UNPAUSE_ADMIN;
    address STAKING_NODES_DELEGATOR_ADMIN;
    address ASSET_MANAGER_ADMIN;
    address EIGEN_STRATEGY_ADMIN;
    address STAKING_NODE_CREATOR;
    address STRATEGY_CONTROLLER;
    address TOKEN_STAKING_NODE_OPERATOR;
    address YN_SECURITY_COUNCIL;
}

struct YnEigenChainAddresses {
    address WSTETH_ADDRESS;
    address WOETH_ADDRESS;
    address STRATEGY_MANAGER;
    address DELEGATION_MANAGER;
}

struct YnEigenImplementations {
    address ynEigen;
    address rateProvider;
    address eigenStrategyManager;
    address tokenStakingNodesManager;
    address tokenStakingNode;
    address assetRegistry;
    address depositAdapter;
    address redemptionAssetsVault;
    address withdrawalQueueManager;
    address lsdWrapper;
}

struct YnEigenProxies {
    ynEigen ynToken;
    EigenStrategyManager eigenStrategyManager;
    TokenStakingNodesManager tokenStakingNodesManager;
    TokenStakingNode tokenStakingNode;
    AssetRegistry assetRegistry;
    ynEigenDepositAdapter ynEigenDepositAdapterInstance;
    IRateProvider rateProvider;
    TimelockController timelock;    
    ynEigenViewer viewer;
    RedemptionAssetsVault redemptionAssetsVault;
    WithdrawalQueueManager withdrawalQueueManager;
    LSDWrapper lsdWrapper;
}

struct YnEigenInit {
    string name;
    string symbol;
    uint256 maxNodeCount;
    address timelock;
    IERC20[] assets;
    IStrategy[] strategies;
    YnEigenActors actors;
    YnEigenChainAddresses chainAddresses;
    YnEigenImplementations implementations;
}
