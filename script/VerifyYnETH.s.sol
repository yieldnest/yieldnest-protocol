/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseYnETHScript} from "script/BaseYnETHScript.s.sol";
import { IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Utils} from "script/Utils.sol";

import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Verify is BaseYnETHScript {

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    bool ONLY_HOLESKY_WITHDRAWALS;

    function run() external {

        ONLY_HOLESKY_WITHDRAWALS = block.chainid == 17000;

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        verifyProxies();
        verifyRoles();
        verifySystemParameters();
        verifyContractDependencies();
        veryifySanityChecks();
    }

    function verifyProxyContract(
        address contractAddress,
        string memory contractName,
        ProxyAddresses memory proxyAddresses
    ) internal view {
        // Verify PROXY_ADMIN_OWNER
        address proxyAdminAddress = Utils.getTransparentUpgradeableProxyAdminAddress(contractAddress);
        address proxyAdminOwner = ProxyAdmin(proxyAdminAddress).owner();
        require(
            proxyAdminOwner == actors.admin.PROXY_ADMIN_OWNER,
            string.concat(contractName, ": PROXY_ADMIN_OWNER mismatch, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(proxyAdminOwner))
        );
        console.log(string.concat("\u2705 ", contractName, ": PROXY_ADMIN_OWNER - ", vm.toString(proxyAdminOwner)));

        // Verify ProxyAdmin address
        require(
            proxyAdminAddress == address(proxyAddresses.proxyAdmin),
            string.concat(contractName, ": ProxyAdmin address mismatch, expected: ", vm.toString(address(proxyAddresses.proxyAdmin)), ", got: ", vm.toString(proxyAdminAddress))
        );
        console.log(string.concat("\u2705 ", contractName, ": ProxyAdmin address - ", vm.toString(proxyAdminAddress)));

        // Verify Implementation address
        address implementationAddress = Utils.getTransparentUpgradeableProxyImplementationAddress(contractAddress);
        require(
            implementationAddress == proxyAddresses.implementation,
            string.concat(contractName, ": Implementation address mismatch, expected: ", vm.toString(proxyAddresses.implementation), ", got: ", vm.toString(implementationAddress))
        );
        console.log(string.concat("\u2705 ", contractName, ": Implementation address - ", vm.toString(implementationAddress)));
    }

    function verifyProxies() internal view {
        verifyProxyContract(
            address(deployment.ynETH),
            "ynETH",
            deployment.proxies.ynETH
        );

        verifyProxyContract(
            address(deployment.rewardsDistributor),
            "rewardsDistributor",
            deployment.proxies.rewardsDistributor
        );

        verifyProxyContract(
            address(deployment.stakingNodesManager),
            "stakingNodesManager",
            deployment.proxies.stakingNodesManager
        );

        verifyProxyContract(
            address(deployment.consensusLayerReceiver),
            "consensusLayerReceiver",
            deployment.proxies.consensusLayerReceiver
        );

        verifyProxyContract(
            address(deployment.executionLayerReceiver),
            "executionLayerReceiver",
            deployment.proxies.executionLayerReceiver
        );

        verifyProxyContract(
            address(deployment.ynViewer),
            "ynViewer",
            deployment.proxies.ynViewer
        );

        // TODO: remove this for mainnet
        if (ONLY_HOLESKY_WITHDRAWALS) { // Holesky chain ID

            verifyProxyContract(
                address(deployment.withdrawalQueueManager),
                "withdrawalQueueManager",
                deployment.proxies.withdrawalQueueManager
            );

            verifyProxyContract(
                address(deployment.ynETHRedemptionAssetsVaultInstance),
                "ynETHRedemptionAssetsVault",
                deployment.proxies.ynETHRedemptionAssetsVault
            );

            verifyProxyContract(
                address(deployment.withdrawalsProcessor),
                "withdrawalsProcessor",
                deployment.proxies.withdrawalsProcessor
            );
        }
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

        // TODO: remove this for mainnet
        if (ONLY_HOLESKY_WITHDRAWALS) { // Holesky chain ID
            // STAKING_NODES_WITHDRAWER_ROLE
            require(
                deployment.stakingNodesManager.hasRole(
                    deployment.stakingNodesManager.STAKING_NODES_WITHDRAWER_ROLE(), 
                    address(deployment.withdrawalsProcessor)
                ), 
                "stakingNodesManager: STAKING_NODES_WITHDRAWER_ROLE INVALID"
            );
            console.log("\u2705 stakingNodesManager: STAKING_NODES_WITHDRAWER_ROLE - ", vm.toString(address(deployment.withdrawalsProcessor)));

            // WITHDRAWAL_MANAGER_ROLE
            require(
                deployment.stakingNodesManager.hasRole(
                    deployment.stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), 
                    address(deployment.withdrawalsProcessor)
                ), 
                "stakingNodesManager: WITHDRAWAL_MANAGER_ROLE INVALID"
            );
            console.log("\u2705 stakingNodesManager: WITHDRAWAL_MANAGER_ROLE - ", vm.toString(address(deployment.withdrawalsProcessor)));
        }

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

 
        if (ONLY_HOLESKY_WITHDRAWALS) {
            // BURNER_ROLE;
            require(
                deployment.ynETH.hasRole(
                    deployment.ynETH.BURNER_ROLE(), 
                    address(deployment.withdrawalQueueManager)
                ), 
                "ynETH: BURNER_ROLE INVALID"
            );
            console.log("\u2705 ynETH: BURNER_ROLE - ", vm.toString(address(deployment.withdrawalQueueManager)));


            //--------------------------------------------------------------------------------------
            //------------------  withdrawalQueueManager roles  ------------------------------------
            //--------------------------------------------------------------------------------------

            // DEFAULT_ADMIN_ROLE
            require(
                deployment.withdrawalQueueManager.hasRole(
                    deployment.withdrawalQueueManager.DEFAULT_ADMIN_ROLE(), 
                    address(actors.admin.ADMIN)
                ), 
                "withdrawalQueueManager: DEFAULT_ADMIN_ROLE INVALID"
            );
            console.log("\u2705 withdrawalQueueManager: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

            // WITHDRAWAL_QUEUE_ADMIN_ROLE
            require(
                deployment.withdrawalQueueManager.hasRole(
                    deployment.withdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE(), 
                    address(actors.admin.ADMIN)
                ), 
                "withdrawalQueueManager: WITHDRAWAL_QUEUE_ADMIN_ROLE INVALID"
            );
            console.log("\u2705 withdrawalQueueManager: WITHDRAWAL_QUEUE_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

            // REQUEST_FINALIZER_ROLE
            require(
                deployment.withdrawalQueueManager.hasRole(
                    deployment.withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), 
                    address(actors.ops.REQUEST_FINALIZER)
                ), 
                "withdrawalQueueManager: REQUEST_FINALIZER_ROLE INVALID"
            );
            console.log("\u2705 withdrawalQueueManager: REQUEST_FINALIZER_ROLE - ", vm.toString(address(actors.ops.REQUEST_FINALIZER)));

            // REDEMPTION_ASSET_WITHDRAWER_ROLE
            require(
                deployment.withdrawalQueueManager.hasRole(
                    deployment.withdrawalQueueManager.REDEMPTION_ASSET_WITHDRAWER_ROLE(), 
                    address(actors.ops.REDEMPTION_ASSET_WITHDRAWER)
                ), 
                "withdrawalQueueManager: REDEMPTION_ASSET_WITHDRAWER_ROLE INVALID"
            );
            console.log("\u2705 withdrawalQueueManager: REDEMPTION_ASSET_WITHDRAWER_ROLE - ", vm.toString(address(actors.ops.REDEMPTION_ASSET_WITHDRAWER)));

            //--------------------------------------------------------------------------------------
            //------------------  ynETHRedemptionAssetsVault roles  ---------------------------------
            //--------------------------------------------------------------------------------------

            // DEFAULT_ADMIN_ROLE
            require(
                deployment.ynETHRedemptionAssetsVaultInstance.hasRole(
                    deployment.ynETHRedemptionAssetsVaultInstance.DEFAULT_ADMIN_ROLE(), 
                    address(actors.admin.ADMIN)
                ), 
                "ynETHRedemptionAssetsVault: DEFAULT_ADMIN_ROLE INVALID"
            );
            console.log("\u2705 ynETHRedemptionAssetsVault: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.PROXY_ADMIN_OWNER)));

            // PAUSER_ROLE
            require(
                deployment.ynETHRedemptionAssetsVaultInstance.hasRole(
                    deployment.ynETHRedemptionAssetsVaultInstance.PAUSER_ROLE(), 
                    address(actors.admin.ADMIN)
                ), 
                "ynETHRedemptionAssetsVault: PAUSER_ROLE INVALID"
            );
            console.log("\u2705 ynETHRedemptionAssetsVault: PAUSER_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

            // UNPAUSER_ROLE
            require(
                deployment.ynETHRedemptionAssetsVaultInstance.hasRole(
                    deployment.ynETHRedemptionAssetsVaultInstance.UNPAUSER_ROLE(), 
                    address(actors.admin.UNPAUSE_ADMIN)
                ), 
                "ynETHRedemptionAssetsVault: UNPAUSER_ROLE INVALID"
            );
            console.log("\u2705 ynETHRedemptionAssetsVault: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

            // Verify redeemer
            require(
                deployment.ynETHRedemptionAssetsVaultInstance.redeemer() == address(deployment.withdrawalQueueManager),
                "ynETHRedemptionAssetsVault: redeemer INVALID"
            );
            console.log("\u2705 ynETHRedemptionAssetsVault: redeemer - ", vm.toString(address(deployment.withdrawalQueueManager)));


            //--------------------------------------------------------------------------------------
            //------------------  WithdrawalsProcessor roles  --------------------------------------
            //--------------------------------------------------------------------------------------

            // DEFAULT_ADMIN_ROLE
            require(
                deployment.withdrawalsProcessor.hasRole(
                    deployment.withdrawalsProcessor.DEFAULT_ADMIN_ROLE(), 
                    address(actors.admin.ADMIN)
                ), 
                "WithdrawalsProcessor: DEFAULT_ADMIN_ROLE INVALID"
            );
            console.log("\u2705 WithdrawalsProcessor: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

            // WITHDRAWAL_MANAGER_ROLE
            require(
                deployment.withdrawalsProcessor.hasRole(
                    deployment.withdrawalsProcessor.WITHDRAWAL_MANAGER_ROLE(), 
                    address(actors.ops.WITHDRAWAL_MANAGER)
                ), 
                "WithdrawalsProcessor: WITHDRAWAL_MANAGER_ROLE INVALID"
            );
            console.log("\u2705 WithdrawalsProcessor: WITHDRAWAL_MANAGER_ROLE - ", vm.toString(address(actors.ops.WITHDRAWAL_MANAGER)));

            // Verify stakingNodesManager
            require(
                address(deployment.withdrawalsProcessor.stakingNodesManager()) == address(deployment.stakingNodesManager),
                "WithdrawalsProcessor: stakingNodesManager INVALID"
            );
            console.log("\u2705 WithdrawalsProcessor: stakingNodesManager - ", vm.toString(address(deployment.stakingNodesManager)));
        }

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


        if (ONLY_HOLESKY_WITHDRAWALS) {
            // EXPECTING 5 BIPS for holesky and 10 BPS for mainnet 
            require(
                deployment.withdrawalQueueManager.withdrawalFee() == (block.chainid == 17000 ? 500 : 1000),
                "WithdrawalQueueManager: withdrawalFee INVALID"
            );
            console.log("\u2705 WithdrawalQueueManager: withdrawalFee - Value:", deployment.withdrawalQueueManager.withdrawalFee());

            console.log("\u2705 All system parameters verified successfully");
        }
    }

    function verifyContractDependencies() internal {

        verifyYnETHDependencies();
        verifyStakingNodesManagerDependencies();
        verifyRewardsDistributorDependencies();
        verifyAllStakingNodeDependencies();

        if (ONLY_HOLESKY_WITHDRAWALS) {
            verifyWithdrawalQueueManagerDependencies();
            verifyYnETHRedemptionAssetsVaultDependencies();
            verifyWithdrawalsProcessorDependencies();
        }

        console.log("\u2705 All contract dependencies verified successfully");
    }

    function verifyWithdrawalsProcessorDependencies() internal view {
        require(
            address(deployment.withdrawalsProcessor.stakingNodesManager()) == address(deployment.stakingNodesManager),
            "WithdrawalsProcessor: stakingNodesManager dependency mismatch"
        );

        console.log("\u2705 WithdrawalsProcessor dependencies verified successfully");
    }

    function verifyYnETHRedemptionAssetsVaultDependencies() internal view {
        require(
            address(deployment.ynETHRedemptionAssetsVaultInstance.ynETH()) == address(deployment.ynETH),
            "YnETHRedemptionAssetsVault: ynETH dependency mismatch"
        );
        require(
            address(deployment.ynETHRedemptionAssetsVaultInstance.redeemer()) == address(deployment.withdrawalQueueManager),
            "YnETHRedemptionAssetsVault: withdrawalQueueManager dependency mismatch"
        );

        console.log("\u2705 YnETHRedemptionAssetsVault dependencies verified successfully");
    }

    function verifyWithdrawalQueueManagerDependencies() internal view {

        require(
            address(deployment.withdrawalQueueManager.redeemableAsset()) == address(deployment.ynETH),
            "WithdrawalQueueManager: redeemableAsset dependency mismatch"
        );
        require(
            address(deployment.withdrawalQueueManager.redemptionAssetsVault()) == address(deployment.ynETHRedemptionAssetsVaultInstance),
            "WithdrawalQueueManager: redemptionAssetsVault dependency mismatch"
        );

        console.log("\u2705 WithdrawalQueueManager dependencies verified successfully");
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
            address(deployment.stakingNodesManager.strategyManager()) == chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS,
            "StakingNodesManager: strategyManager dependency mismatch"
        );

        require(
            address(deployment.stakingNodesManager.upgradeableBeacon().implementation()) == address(deployment.stakingNodeImplementation),
            "StakingNodesManager: upgradeableBeacon implementation mismatch"
        );

        if (ONLY_HOLESKY_WITHDRAWALS) {
            require(
                address(deployment.stakingNodesManager.redemptionAssetsVault()) == address(deployment.ynETHRedemptionAssetsVaultInstance),
                "StakingNodesManager: redemptionAssetsVault dependency mismatch"
            );
            console.log("\u2705 StakingNodesManager: redemptionAssetsVault dependency verified");
        }
        
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

            console.log("StakingNode address:", address(stakingNode));
            console.log("EigenPod address:", address(stakingNode.eigenPod()));
            assert(
                address(stakingNode.eigenPod()) == storedPod
            );
            console.log("\u2705 StakingNode dependencies verified for node", i);
        }
    }

    function veryifySanityChecks() internal view {
        // Check that previewDeposit of 1 ETH is less than 1 ether
        uint256 previewDepositResult = deployment.ynETH.previewDeposit(1 ether);
        require(previewDepositResult < 1 ether, "previewDeposit of 1 ETH should be less than 1 ether");
        console.log("\u2705 previewDeposit of 1 ETH is less than 1 ether");

        // Check that totalSupply is less than totalAssets
        uint256 totalSupply = deployment.ynETH.totalSupply();
        uint256 totalAssets = deployment.ynETH.totalAssets();
        require(totalSupply < totalAssets, "totalSupply should be less than totalAssets");
        console.log("\u2705 totalSupply is less than totalAssets");

        // Print totalSupply and totalAssets
        console.log(string.concat("Total Supply: ", vm.toString(totalSupply), " ynETH (", vm.toString(totalSupply / 1e18), " units)"));
        console.log(string.concat("Total Assets: ", vm.toString(totalAssets), " wei (", vm.toString(totalAssets / 1e18), " ETH)"));

        // Check previewRedeem for Holesky withdrawals
        if (ONLY_HOLESKY_WITHDRAWALS) {
            uint256 previewRedeemResult = deployment.ynETH.previewRedeem(1 ether);
            console.log(string.concat("previewRedeem of 1 ynETH: ", vm.toString(previewRedeemResult), " wei (", vm.toString(previewRedeemResult / 1e18), " ETH)"));
        }

        // Check that ETH balance of ynETH + redemption assets vault + staking nodes equals totalAssets
        uint256 ynETHBalance = address(deployment.ynETH).balance;
        uint256 redemptionVaultBalance = ONLY_HOLESKY_WITHDRAWALS ? address(deployment.ynETHRedemptionAssetsVaultInstance).balance : 0;
        
        uint256 stakingNodesBalance = 0;
        IStakingNode[] memory stakingNodes = deployment.stakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < stakingNodes.length; i++) {
            stakingNodesBalance += stakingNodes[i].getETHBalance();
        }

        uint256 totalCalculatedBalance = ynETHBalance + redemptionVaultBalance + stakingNodesBalance;
        require(totalCalculatedBalance == totalAssets, "Sum of balances should equal totalAssets");
        console.log("\u2705 Sum of ETH balances equals totalAssets");

        // Assert the correct number of staking nodes for mainnet and holesky
        uint256 expectedNodeCount = block.chainid == 1 ? 5 : (block.chainid == 17000 ? 3 : 0);
        uint256 actualNodeCount = stakingNodes.length;
        require(
            actualNodeCount == expectedNodeCount,
            string.concat(
                "Incorrect number of staking nodes. Expected: ",
                vm.toString(expectedNodeCount),
                ", Actual: ",
                vm.toString(actualNodeCount)
            )
        );
        console.log(
            string.concat(
                "\u2705 Correct number of staking nodes: ",
                vm.toString(actualNodeCount)
            )
        );

        // Check ynViewer getRate is greater than 1 ether
        uint256 ynETHRate = deployment.ynViewer.getRate();
        require(ynETHRate > 1 ether, "ynETH rate should be greater than 1 ether");
        console.log(string.concat("\u2705 ynETH rate is greater than 1 ether: ", vm.toString(ynETHRate), " wei (", vm.toString(ynETHRate / 1e18), " ETH)"));
    }
}