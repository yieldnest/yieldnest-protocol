// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";

contract PrintYnEigenState is BaseYnEigenScript {
    Deployment deployment;

    function run() external {
        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        printYnEigenState();
        printEigenStrategyManagerState();
        printTokenStakingNodesManagerState();
        printTokenStakingNodesState();
    }

    function printYnEigenState() internal view {
        console.log("======= ynEIGEN Contract State =======");
        console.log("Address:", address(deployment.ynEigen));
        console.log("Total Supply:", deployment.ynEigen.totalSupply());
        console.log("Total Assets:", deployment.ynEigen.totalAssets());
        console.log("Exchange Rate:", deployment.viewer.getRate());
        
        console.log("Preview Redeem (1 ynEIGEN):", deployment.ynEigen.previewRedeem(1 ether));        
        console.log("");
    }

    function printEigenStrategyManagerState() internal view {
        console.log("======= Eigen Strategy Manager State =======");
        console.log("Address:", address(deployment.eigenStrategyManager));
        console.log("ynEigen:", address(deployment.eigenStrategyManager.ynEigen()));
        console.log("EigenLayer Strategy Manager:", address(deployment.eigenStrategyManager.strategyManager()));
        console.log("EigenLayer Delegation Manager:", address(deployment.eigenStrategyManager.delegationManager()));
        console.log("Token Staking Nodes Manager:", address(deployment.eigenStrategyManager.tokenStakingNodesManager()));
        
        IERC20[] memory assets = deployment.assetRegistry.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = deployment.eigenStrategyManager.strategies(assets[i]);
            console.log(string.concat("Strategy for ", ERC20(address(assets[i])).symbol(), ":"), address(strategy));

            EigenStrategyManager.StrategyBalance memory strategyBalance;
            (strategyBalance.stakedBalance, strategyBalance.withdrawnBalance) = deployment.eigenStrategyManager.strategiesBalance(strategy);
            console.log("Staked Balance for strategy: ", ERC20(address(assets[i])).symbol(), ":", strategyBalance.stakedBalance);
            console.log("Withdrawn Balance for strategy:", ERC20(address(assets[i])).symbol(), ":", strategyBalance.withdrawnBalance);
        }
        
        console.log("");
    }

    function printTokenStakingNodesManagerState() internal view {
        console.log("======= Token Staking Nodes Manager State =======");
        console.log("Address:", address(deployment.tokenStakingNodesManager));
        console.log("Node Count:", deployment.tokenStakingNodesManager.getAllNodes().length);
        console.log("Max Node Count:", deployment.tokenStakingNodesManager.maxNodeCount());
        console.log("Yield Nest Strategy Manager:", address(deployment.tokenStakingNodesManager.yieldNestStrategyManager()));
        console.log("EigenLayer Delegation Manager:", address(deployment.tokenStakingNodesManager.delegationManager()));
        console.log("EigenLayer Strategy Manager:", address(deployment.tokenStakingNodesManager.strategyManager()));
        console.log("Rewards Coordinator:", address(deployment.tokenStakingNodesManager.rewardsCoordinator()));
        console.log("Token Staking Node Implementation:", address(deployment.tokenStakingNodesManager.upgradeableBeacon().implementation()));
        
        console.log("");
    }

    function printTokenStakingNodesState() internal  {
        ITokenStakingNode[] memory stakingNodes = deployment.tokenStakingNodesManager.getAllNodes();
        IERC20[] memory assets = deployment.assetRegistry.getAssets();
        
        console.log("======= Token Staking Nodes State =======");
        console.log("Total Nodes:", stakingNodes.length);
        
        for (uint256 i = 0; i < stakingNodes.length; i++) {
            ITokenStakingNode node = stakingNodes[i];
            console.log("--- Node", i, "---");
            console.log("Address:", address(node));
            console.log("Node ID:", node.nodeId());
            console.log("Delegated To:", node.delegatedTo());
            console.log("Is Synchronized:", node.isSynchronized());
            console.log("Implementation:", node.implementation());
            console.log("Initialized Version:", node.getInitializedVersion());
            
            // Print queued shares and withdrawals for each asset
            console.log("Assets State:");
            for (uint256 j = 0; j < assets.length; j++) {
                string memory assetSymbol = ERC20(address(assets[j])).symbol();
                IStrategy strategy = deployment.eigenStrategyManager.strategies(assets[j]);
                
                // (uint256 queuedShares, uint256 withdrawnShares) = node.getQueuedSharesAndWithdrawn(strategy, assets[j]);
                
                console.log(string.concat("  ", assetSymbol, ":"));
                console.log("    Strategy:", address(strategy));
                // console.log("    Pre-ELIP002 Queued Shares:", node.preELIP002QueuedSharesAmount(strategy));
                console.log("    Post-ELIP002 Queued Shares:", node.queuedShares(strategy));
                // console.log("    Total Queued Shares:", queuedShares);
                // console.log("    Withdrawn Shares:", withdrawnShares);
            }
            
            console.log("");
        }
    }
}
