/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import { IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Utils} from "script/Utils.sol";

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

        verifyProxyAdminOwners();
        verifyRoles();
        verifySystemParameters();
        verifyContractDependencies();
    }

    function verifyProxyAdminOwners() internal view {
        address ynETHAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynETH))).owner();
        require(
            ynETHAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("ynETH: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(ynETHAdmin))
        );
        console.log("\u2705 ynETH: PROXY_ADMIN_OWNER - ", vm.toString(ynETHAdmin));

        address rewardsDistributorAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.rewardsDistributor))).owner();
        require(
            rewardsDistributorAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("rewardsDistributor: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(rewardsDistributorAdmin))
        );
        console.log("\u2705 rewardsDistributor: PROXY_ADMIN_OWNER - ", vm.toString(rewardsDistributorAdmin));

        address stakingNodesManagerAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.stakingNodesManager))).owner();
        require(
            stakingNodesManagerAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("stakingNodesManager: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(stakingNodesManagerAdmin))
        );
        console.log("\u2705 stakingNodesManager: PROXY_ADMIN_OWNER - ", vm.toString(stakingNodesManagerAdmin));

        address consensusLayerReceiverAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.consensusLayerReceiver))).owner();
        require(
            consensusLayerReceiverAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("consensusLayerReceiver: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(consensusLayerReceiverAdmin))
        );
        console.log("\u2705 consensusLayerReceiver: PROXY_ADMIN_OWNER - ", vm.toString(consensusLayerReceiverAdmin));

        address executionLayerReceiverAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.executionLayerReceiver))).owner();
        require(
            executionLayerReceiverAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("executionLayerReceiver: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(executionLayerReceiverAdmin))
        );
        console.log("\u2705 executionLayerReceiver: PROXY_ADMIN_OWNER - ", vm.toString(executionLayerReceiverAdmin));
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
        console.log("\u2705 consensusLayerReceiver: WITHDRAWER_ROLE - ", vm.toString(address(deployment.rewardsDistributor)));

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.consensusLayerReceiver.hasRole(
                deployment.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "consensusLayerReceiver: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 consensusLayerReceiver: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));


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
        console.log("\u2705 executionLayerReceiver: WITHDRAWER_ROLE - ", vm.toString(address(deployment.rewardsDistributor)));

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.executionLayerReceiver.hasRole(
                deployment.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "executionLayerReceiver: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 executionLayerReceiver: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

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
        console.log("\u2705 rewardsDistributor: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // REWARDS_ADMIN_ROLE
        require(
            deployment.rewardsDistributor.hasRole(
                deployment.rewardsDistributor.REWARDS_ADMIN_ROLE(), 
                address(actors.admin.REWARDS_ADMIN)
            ), 
            "rewardsDistributor: REWARDS_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 rewardsDistributor: REWARDS_ADMIN_ROLE - ", vm.toString(address(actors.admin.REWARDS_ADMIN)));

        // FEE_RECEIVER
        require(
            deployment.rewardsDistributor.feesReceiver() == actors.admin.FEE_RECEIVER, 
            "rewardsDistributor: FEE_RECEIVER INVALID"
        );
        console.log("\u2705 rewardsDistributor: FEE_RECEIVER - ", vm.toString(actors.admin.FEE_RECEIVER));

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
        console.log("\u2705 stakingNodesManager: STAKING_ADMIN_ROLE - ", vm.toString(address(actors.admin.STAKING_ADMIN)));

        // STAKING_NODES_OPERATOR_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODES_OPERATOR_ROLE(), 
                address(actors.ops.STAKING_NODES_OPERATOR)
            ), 
            "stakingNodesManager: STAKING_NODES_OPERATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODES_OPERATOR_ROLE - ", vm.toString(address(actors.ops.STAKING_NODES_OPERATOR)));

        // VALIDATOR_MANAGER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.VALIDATOR_MANAGER_ROLE(), 
                address(actors.ops.VALIDATOR_MANAGER)
            ), 
            "stakingNodesManager: VALIDATOR_MANAGER_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: VALIDATOR_MANAGER_ROLE - ", vm.toString(address(actors.ops.VALIDATOR_MANAGER)));

        // STAKING_NODE_CREATOR_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODE_CREATOR_ROLE(), 
                address(actors.ops.STAKING_NODE_CREATOR)
            ), 
            "stakingNodesManager: STAKING_NODE_CREATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODE_CREATOR_ROLE - ", vm.toString(address(actors.ops.STAKING_NODE_CREATOR)));

        // STAKING_NODES_DELEGATOR_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.STAKING_NODES_DELEGATOR_ROLE(), 
                address(actors.admin.STAKING_NODES_DELEGATOR)
            ), 
            "stakingNodesManager: STAKING_NODES_DELEGATOR_ROLE INVALID"
        );
        console.log("\u2705 stakingNodesManager: STAKING_NODES_DELEGATOR_ROLE - ", vm.toString(address(actors.admin.STAKING_NODES_DELEGATOR)));

        // PAUSER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "stakingNodesManager: PAUSE_ADMIN INVALID"
        );
        console.log("\u2705 stakingNodesManager: PAUSE_ADMIN - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.stakingNodesManager.hasRole(
                deployment.stakingNodesManager.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "stakingNodesManager: UNPAUSE_ADMIN INVALID"
        );
        console.log("\u2705 stakingNodesManager: UNPAUSE_ADMIN - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));


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
        console.log("\u2705 ynETH: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE;
        require(
            deployment.ynETH.hasRole(
                deployment.ynETH.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "ynETH: PAUSER_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynETH: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE;
        require(
            deployment.ynETH.hasRole(
                deployment.ynETH.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "ynETH: UNPAUSER_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynETH: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

    }

    function verifySystemParameters() internal view {
        // Verify the system parameters
        require(
            deployment.rewardsDistributor.feesBasisPoints() == 1000,
            "ynETH: feesBasisPoints INVALID"
        );
        console.log("\u2705 ynETH: feesBasisPoints - Value:", deployment.rewardsDistributor.feesBasisPoints());

        require(
            deployment.ynETH.depositsPaused() == false,
            "ynETH: depositsPaused INVALID"
        );
        console.log("\u2705 ynETH: depositsPaused - Value:", deployment.ynETH.depositsPaused());

        require(
            deployment.stakingNodesManager.maxNodeCount() == 10,
            "ynETH: maxNodeCount INVALID"
        );
        console.log("\u2705 ynETH: maxNodeCount - Value:", deployment.stakingNodesManager.maxNodeCount());

        require(
            deployment.stakingNodesManager.validatorRegistrationPaused() == false,
            "ynETH: validatorRegistrationPaused INVALID"
        );
        console.log("\u2705 ynETH: validatorRegistrationPaused - Value:", deployment.stakingNodesManager.validatorRegistrationPaused());

        console.log("\u2705 All system parameters verified successfully");
    }

    function verifyContractDependencies() internal {

        verifyYnETHDependencies();
        verifyStakingNodesManagerDependencies();
        verifyRewardsDistributorDependencies();
        verifyAllStakingNodeDependencies();

        console.log("\u2705 All contract dependencies verified successfully");
    }

    function verifyYnETHDependencies() internal view {
        // Verify ynETH contract dependencies
        require(
            address(deployment.ynETH.rewardsDistributor()) == address(deployment.rewardsDistributor),
            "ynETH: RewardsDistributor dependency mismatch"
        );
        require(
            address(deployment.ynETH.stakingNodesManager()) == address(deployment.stakingNodesManager),
            "ynETH: StakingNodesManager dependency mismatch"
        );

        console.log("\u2705 ynETH dependencies verified successfully");
    }

    function verifyRewardsDistributorDependencies() internal view {
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

        console.log("\u2705 RewardsDistributor dependencies verified");
    }

    function verifyStakingNodesManagerDependencies() internal view {
        require(
            address(deployment.stakingNodesManager.ynETH()) == address(deployment.ynETH),
            "StakingNodesManager: ynETH dependency mismatch"
        );

        require(
            address(deployment.stakingNodesManager.rewardsDistributor()) == address(deployment.rewardsDistributor),
            "StakingNodesManager: rewardsDistributor dependency mismatch"
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

        require(
            address(deployment.stakingNodesManager.upgradeableBeacon().implementation()) == address(deployment.stakingNodeImplementation),
            "StakingNodesManager: upgradeableBeacon implementation mismatch"
        );
        
        console.log("\u2705 StakingNodesManager dependencies verified");
    }

    function verifyAllStakingNodeDependencies() internal view {
        IStakingNode[] memory stakingNodes = deployment.stakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < stakingNodes.length; i++) {
            IStakingNode stakingNode = stakingNodes[i];
            require(
                address(stakingNode.stakingNodesManager()) == address(deployment.stakingNodesManager),
                "StakingNode: StakingNodesManager dependency mismatch"
            );

            address storedPod = address(IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS).ownerToPod(address(stakingNode)));
            assert(
                address(stakingNode.eigenPod()) == storedPod
            );
            console.log("\u2705 StakingNode dependencies verified for node", i);
        }
    }
}