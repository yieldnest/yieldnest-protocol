/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Verify is BaseScript {

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        verifyRoles();
        verifySystemParameters();
        verifyContractDependencies();
    }

    function verifyRoles() internal view {

        //--------------------------------------------------------------------------------------
        //----------------  consesusLayerReceiver roles  ---------------------------------------
        //--------------------------------------------------------------------------------------
        // WITHDRAWER_ROLE
        require(
            deployment.consensusLayerReceiver.hasRole(
                deployment.consensusLayerReceiver.WITHDRAWER_ROLE(), 
                address(deployment.rewardsDistributor)
            ), 
            "consensusLayerReceiver: WITHDRAWER_ROLE INVALID"
        );
        console.log("\u2705 consensusLayerReceiver: WITHDRAWER_ROLE");

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.consensusLayerReceiver.hasRole(
                deployment.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "consensusLayerReceiver: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 consensusLayerReceiver: DEFAULT_ADMIN_ROLE");


        //--------------------------------------------------------------------------------------
        //---------------  executionLayerReceiver roles  ---------------------------------------
        //--------------------------------------------------------------------------------------		
        // WITHDRAWER_ROLE
        require(
            deployment.executionLayerReceiver.hasRole(
                deployment.executionLayerReceiver.WITHDRAWER_ROLE(),
                address(deployment.rewardsDistributor)
            ), 
            "executionLayerReceiver: WITHDRAWER_ROLE INVALID"
        );
        console.log("\u2705 executionLayerReceiver: WITHDRAWER_ROLE");

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.executionLayerReceiver.hasRole(
                deployment.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "executionLayerReceiver: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 executionLayerReceiver: DEFAULT_ADMIN_ROLE");

        //--------------------------------------------------------------------------------------
        //-------------------  rewardsDistributor roles  ---------------------------------------
        //--------------------------------------------------------------------------------------	
        // DEFAULT_ADMIN_ROLE
        require(
            deployment.rewardsDistributor.hasRole(
                deployment.rewardsDistributor.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "rewardsDistributor: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 rewardsDistributor: DEFAULT_ADMIN_ROLE");

        // FEE_RECEIVER
        require(
            deployment.rewardsDistributor.feesReceiver() == actors.admin.FEE_RECEIVER, 
            "rewardsDistributor: FEE_RECEIVER INVALID"
        );
        console.log("\u2705 rewardsDistributor: FEE_RECEIVER");

        //--------------------------------------------------------------------------------------
        //------------------  stakingNodesManager roles  ---------------------------------------
        //--------------------------------------------------------------------------------------			
        // STAKING_ADMIN_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_ADMIN_ROLE(), 
                address(actors.admin.STAKING_ADMIN)
            ), 
            "stakingNodesManager: STAKING_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_ADMIN_ROLE");

        // STAKING_NODES_ADMIN_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODES_OPERATOR_ROLE(), 
                address(actors.ops.STAKING_NODES_OPERATOR)
            ), 
            "stakingNodesManager: STAKING_NODES_OPERATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODES_ADMIN_ROLE");

        // VALIDATOR_MANAGER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.VALIDATOR_MANAGER_ROLE(), 
                address(actors.ops.VALIDATOR_MANAGER)
            ), 
            "stakingNodesManager: VALIDATOR_MANAGER_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: VALIDATOR_MANAGER_ROLE");

        // STAKING_NODE_CREATOR_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODE_CREATOR_ROLE(), 
                address(actors.ops.STAKING_NODE_CREATOR)
            ), 
            "stakingNodesManager: STAKING_NODE_CREATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODE_CREATOR_ROLE");

        // PAUSER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.PAUSER_ROLE(), 
                address(actors.admin.PAUSE_ADMIN)
            ), 
            "stakingNodesManager: PAUSE_ADMIN INVALID"
        );
        console.log("\u2705 stakingNodesManager: PAUSE_ADMIN");

        //--------------------------------------------------------------------------------------
        //--------------------------------  ynETH roles  ---------------------------------------
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.ynETH.hasRole(
                deployment.ynETH.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "ynETH: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynETH: DEFAULT_ADMIN_ROLE");

        // PAUSER_ROLE;
        require(
            deployment.ynETH.hasRole(
                deployment.ynETH.PAUSER_ROLE(), 
                address(actors.admin.PAUSE_ADMIN)
            ), 
            "ynETH: PAUSER_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynETH: PAUSER_ROLE");

        // STAKING_NODES_MANAGER
        require(
            address(deployment.ynETH.stakingNodesManager()) == address(deployment.stakingNodesManager), 
            "ynETH: stakingNodesManager INVALID"
        );
        console.log("\u2705 ynETH: stakingNodesManager");

        // REWARDS_DISTRIBUTOR
        require(
            address(deployment.ynETH.rewardsDistributor()) == address(deployment.rewardsDistributor),
            "ynETH: rewardsDistributor INVALID"
        );
        console.log("\u2705 ynETH: rewardsDistributor");

    }

    function verifySystemParameters() internal view {
        // Verify the system parameters
        console.log("\u2705 ynETH: feesBasisPoints");
        require(
            deployment.rewardsDistributor.feesBasisPoints() == 1000,
            "ynETH: feesBasisPoints INVALID"
        );
    }

    function verifyContractDependencies() internal view {

        // Verify ynETH contract dependencies
        require(
            address(deployment.ynETH.rewardsDistributor()) == address(deployment.rewardsDistributor),
            "ynETH: rewardsDistributor dependency mismatch"
        );
        require(
            address(deployment.ynETH.stakingNodesManager()) == address(deployment.stakingNodesManager),
            "ynETH: stakingNodesManager dependency mismatch"
        );

        // Verify RewardsDistributor contract dependencies
        require(
            address(deployment.rewardsDistributor.ynETH()) == address(deployment.ynETH),
            "RewardsDistributor: ynETH dependency mismatch"
        );
        require(
            address(deployment.rewardsDistributor.executionLayerReceiver()) == address(deployment.executionLayerReceiver),
            "RewardsDistributor: executionLayerReceiver dependency mismatch"
        );
        require(
            address(deployment.rewardsDistributor.consensusLayerReceiver()) == address(deployment.consensusLayerReceiver),
            "RewardsDistributor: consensusLayerReceiver dependency mismatch"
        );

        require(
            address(deployment.stakingNodesManager.ynETH()) == address(deployment.ynETH),
            "StakingNodesManager: ynETH dependency mismatch"
        );
        require(
            address(deployment.stakingNodesManager.eigenPodManager()) == chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS,
            "StakingNodesManager: eigenPodManager dependency mismatch"
        );
        require(
            address(deployment.stakingNodesManager.depositContractEth2()) == chainAddresses.ethereum.DEPOSIT_2_ADDRESS,
            "StakingNodesManager: depositContractEth2 dependency mismatch"
        );
        require(
            address(deployment.stakingNodesManager.delegationManager()) == chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS,
            "StakingNodesManager: delegationManager dependency mismatch"
        );
        require(
            address(deployment.stakingNodesManager.delayedWithdrawalRouter()) == chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS,
            "StakingNodesManager: delayedWithdrawalRouter dependency mismatch"
        );
        require(
            address(deployment.stakingNodesManager.strategyManager()) == chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS,
            "StakingNodesManager: strategyManager dependency mismatch"
        );
        
        console.log("\u2705 StakingNodesManager dependencies verified");

        console.log("\u2705 All contract dependencies verified successfully");
    }
}