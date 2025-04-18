// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

contract PrintYnEthState is BaseYnETHScript {
    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function run() external {
        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        printYnETHState();
        printStakingNodesManagerState();
        printStakingNodesState();
    }

    function printYnETHState() internal view {
        console.log("======= ynETH Contract State =======");
        console.log("Address:", address(deployment.ynETH));
        console.log("Total Supply:", deployment.ynETH.totalSupply());
        console.log("Total Assets:", deployment.ynETH.totalAssets());
        console.log("Raw ETH Balance:", address(deployment.ynETH).balance);
        console.log("Total Deposited in pool:", deployment.ynETH.totalDepositedInPool());
        console.log("Preview Redeem (1 ynETH):", deployment.ynETH.previewRedeem(1 ether));
        
    }

    function printStakingNodesManagerState() internal view {
        console.log("======= StakingNodesManager State =======");
        console.log("Address:", address(deployment.stakingNodesManager));
        console.log("Node Count:", deployment.stakingNodesManager.getAllNodes().length);
        console.log("Max Node Count:", deployment.stakingNodesManager.maxNodeCount());
        console.log("Delegation Manager:", address(deployment.stakingNodesManager.delegationManager()));
        console.log("Strategy Manager:", address(deployment.stakingNodesManager.strategyManager()));
        console.log("EigenPod Manager:", address(deployment.stakingNodesManager.eigenPodManager()));
        console.log("Rewards Coordinator:", address(deployment.stakingNodesManager.rewardsCoordinator()));
        console.log("Staking Node Implementation:", address(deployment.stakingNodesManager.upgradeableBeacon().implementation()));
        console.log("Total ETH Staked:", deployment.stakingNodesManager.totalETHStaked());
    }

    function printStakingNodesState() internal view {
        IStakingNode[] memory stakingNodes = deployment.stakingNodesManager.getAllNodes();
        console.log("======= Staking Nodes State =======");
        console.log("Total Nodes:", stakingNodes.length);
        
        for (uint256 i = 0; i < stakingNodes.length; i++) {
            IStakingNode node = stakingNodes[i];
            console.log("--- Node", i, "---");
            console.log("Address:", address(node));
            console.log("Node ID:", node.nodeId());
            console.log("ETH Balance:", node.getETHBalance());
            console.log("Unverified Staked ETH:", node.getUnverifiedStakedETH());
            console.log("Queued Shares Amount:", node.getQueuedSharesAmount());


            try node.preELIP002QueuedSharesAmount() returns (uint256 shares) {
                console.log("Pre-ELIP002 Queued Shares:", shares);
            } catch {
                console.log("Pre-ELIP002 Queued Shares: Not available");
            }

            console.log("Withdrawn ETH:", node.getWithdrawnETH());
            console.log("Is Synchronized:", node.isSynchronized());
            console.log("EigenPod:", address(node.eigenPod()));
            console.log("Implementation:", node.implementation());
            console.log("Initialized Version:", node.getInitializedVersion());
            console.log("Delegated To:", node.delegatedTo());
            console.log("");
        }
    }
}
