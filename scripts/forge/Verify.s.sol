/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseScript} from "scripts/forge/BaseScript.s.sol";
import {ActorAddresses} from "scripts/forge/Actors.sol";
import {console} from "lib/forge-std/src/Console.sol";

contract Verify is BaseScript {

    Deployment deployment;
    ActorAddresses.Actors actors;

    function run() external {

        deployment = loadDeployment();
        actors = getActors();

        verifyRoles();
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
                address(actors.ADMIN)
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
                address(actors.ADMIN)
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
                address(actors.ADMIN)
            ), 
            "rewardsDistributor: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 rewardsDistributor: DEFAULT_ADMIN_ROLE");

        //--------------------------------------------------------------------------------------
        //------------------  stakingNodesManager roles  ---------------------------------------
        //--------------------------------------------------------------------------------------			
        // STAKING_ADMIN_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_ADMIN_ROLE(), 
                address(actors.STAKING_ADMIN)
            ), 
            "stakingNodesManager: STAKING_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_ADMIN_ROLE");

        // STAKING_NODES_ADMIN_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODES_ADMIN_ROLE(), 
                address(actors.STAKING_NODES_ADMIN)
            ), 
            "stakingNodesManager: STAKING_NODES_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODES_ADMIN_ROLE");

        // VALIDATOR_MANAGER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.VALIDATOR_MANAGER_ROLE(), 
                address(actors.VALIDATOR_MANAGER)
            ), 
            "stakingNodesManager: VALIDATOR_MANAGER_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: VALIDATOR_MANAGER_ROLE");

        // STAKING_NODE_CREATOR_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODE_CREATOR_ROLE(), 
                address(actors.STAKING_NODE_CREATOR)
            ), 
            "stakingNodesManager: STAKING_NODE_CREATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODE_CREATOR_ROLE");

        // PAUSER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.PAUSER_ROLE(), 
                address(actors.PAUSE_ADMIN)
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
                address(actors.ADMIN)
            ), 
            "ynETH: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynETH: DEFAULT_ADMIN_ROLE");

        // PAUSER_ROLE;
        require(
            deployment.ynETH.hasRole(
                deployment.ynETH.PAUSER_ROLE(), 
                address(actors.PAUSE_ADMIN)
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

    




}