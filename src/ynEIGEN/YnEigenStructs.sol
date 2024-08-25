// SPDX-License-Identifier: BSD-3-Clause License
pragma solidity ^0.8.24;

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
}

struct YnEigenChainAddresses {
    address WSTETH_ADDRESS;
    address WOETH_ADDRESS;
    address STRATEGY_MANAGER;
    address DELEGATION_MANAGER;
}

struct YnEigenImplementations {
    address ynEigen;
    address eigenStrategyManager;
    address tokenStakingNodesManager;
    address tokenStakingNode;
    address assetRegistry;
    address depositAdapter;
    address rateProvider;
    address viewer;
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
