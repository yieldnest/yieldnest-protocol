// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
// import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWETH} from "src/external/tokens/IWETH.sol";

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ynETH} from "src/ynETH.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {ActorAddresses} from "script/Actors.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";

import {console} from "lib/forge-std/src/console.sol";

contract DeployYnETHWithdrawals is BaseYnETHScript {


    struct WithdrawalsDeployment {
        ynETHRedemptionAssetsVault ynETHRedemptionAssetsVault;
        WithdrawalQueueManager withdrawalQueueManager;
        WithdrawalsProcessor withdrawalsProcessor;
        StakingNodesManager stakingNodesManagerImplementation;
        StakingNode stakingNodeImplementation;
        ynETH ynETHImplementation;
    }

    /**
        The following uprades MUST be performed for withdrawals to work:

        ynETH.sol
        StakingNodesManager.sol
        StakingNodeImplementation.sol
     */

    ynETHRedemptionAssetsVault public ynETHRedemptionAssetsVaultInstance;
    WithdrawalQueueManager public ynETHWithdrawalQueueManager;
    WithdrawalsProcessor withdrawalsProcessor;
    StakingNodesManager stakingNodesManagerImplementation;
    StakingNode stakingNodeImplementation;
    ynETH ynETHImplementation;
    ActorAddresses.Actors actors;
    address deployer;

    function run() external {

        // ynETH.sol ROLES
        actors = getActors();
        
        ContractAddresses contractAddresses = new ContractAddresses();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);
        deployer = publicKey;

        IynETH yneth = IynETH(payable(contractAddresses.getChainAddresses(block.chainid).yn.YNETH_ADDRESS));
        // Get the StakingNodesManager instance
        IStakingNodesManager stakingNodesManager = IStakingNodesManager(contractAddresses.getChainAddresses(block.chainid).yn.STAKING_NODES_MANAGER_ADDRESS);

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);
        
        // Deploy implementation contracts
        stakingNodesManagerImplementation = new StakingNodesManager();
        console.log("StakingNodesManager implementation deployed at:", address(stakingNodesManagerImplementation));

        StakingNode stakingNodeImplementation = new StakingNode();
        console.log("StakingNode implementation deployed at:", address(stakingNodeImplementation));

        ynETHImplementation = new ynETH();
        console.log("ynETH implementation deployed at:", address(ynETHImplementation));

        // deploy ynETHRedemptionAssetsVault
        {
            ynETHRedemptionAssetsVault impl = new ynETHRedemptionAssetsVault();
            console.log("ynETHRedemptionAssetsVault implementation deployed at:", address(impl));
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(impl),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            WithdrawalQueueManager withdrawalQueueManagerImpl = new WithdrawalQueueManager();
            console.log("WithdrawalQueueManager implementation deployed at:", address(withdrawalQueueManagerImpl));

            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(withdrawalQueueManagerImpl),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
        }

        // deploy WithdrawalsProcessor
        {
            WithdrawalsProcessor withdrawalsProcessorImplementation = new WithdrawalsProcessor();
            console.log("WithdrawalsProcessor implementation deployed at:", address(withdrawalsProcessorImplementation));

            TransparentUpgradeableProxy withdrawalsProcessorProxy = new TransparentUpgradeableProxy(
                address(withdrawalsProcessorImplementation),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            withdrawalsProcessor = WithdrawalsProcessor(address(withdrawalsProcessorProxy));
        }

        // initialize ynETHRedemptionAssetsVault
        {
            ynETHRedemptionAssetsVault.Init memory _init = ynETHRedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(ynETHWithdrawalQueueManager),
                ynETH: IynETH(address(yneth))
            });
            ynETHRedemptionAssetsVaultInstance.initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory managerInit = WithdrawalQueueManager.Init({
                name: "ynETH Withdrawal Manager",
                symbol: "ynETHWM",
                redeemableAsset: IRedeemableAsset(address(yneth)),
                redemptionAssetsVault: IRedemptionAssetsVault(address(ynETHRedemptionAssetsVaultInstance)),
                admin: actors.admin.ADMIN,
                withdrawalQueueAdmin: actors.admin.ADMIN,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                withdrawalFee: 1000, // 0.1%
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            ynETHWithdrawalQueueManager.initialize(managerInit);
        }

        {
            // initialize WithdrawalsProcessor
            withdrawalsProcessor.initialize(
                IStakingNodesManager(address(stakingNodesManager)),
                actors.admin.ADMIN,
                actors.ops.WITHDRAWAL_MANAGER
            );
            console.log("WithdrawalsProcessor initialized");

        }

        // Perform the following permissioned call with DEFAULT_ADMIN ROLE:

        console.log("Parameters for stakingNodesManager.initializeV2:");
        console.log("redemptionAssetsVault:", address(ynETHRedemptionAssetsVaultInstance));
        console.log("withdrawalManager:", address(withdrawalsProcessor));
        console.log("stakingNodesWithdrawer:", address(withdrawalsProcessor));

        // Save deployment information
        WithdrawalsDeployment memory deployment = WithdrawalsDeployment({
            ynETHRedemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
            withdrawalQueueManager: ynETHWithdrawalQueueManager,
            withdrawalsProcessor: withdrawalsProcessor,
            stakingNodesManagerImplementation: stakingNodesManagerImplementation,
            stakingNodeImplementation: stakingNodeImplementation,
            ynETHImplementation: ynETHImplementation
        });

        saveWithdrawalsDeployment(deployment);

        // Verify all the above is deployed correctly.
        verifyDeployment(contractAddresses, deployment);

        console.log("Deployment information saved successfully.");

        // initialize stakingNodesManager withdrawal contracts
        {
            StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
                redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
                withdrawalManager: address(withdrawalsProcessor),
                stakingNodesWithdrawer: address(withdrawalsProcessor)
            });

            console.log("actors.ops.WITHDRAWAL_MANAGER:", actors.ops.WITHDRAWAL_MANAGER);
            console.log("actors.ops.STAKING_NODES_WITHDRAWER:", actors.ops.STAKING_NODES_WITHDRAWER);
            
            bytes memory txData = abi.encodeWithSelector(StakingNodesManager.initializeV2.selector, initParams);
            console.log("Transaction data for stakingNodesManager.initializeV2:");
            console.logBytes(txData);
        }

        vm.stopBroadcast();
    }


    function getDeploymentFile() internal virtual view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/ynETHWithdrawals-", vm.toString(block.chainid), ".json");
    }

    function saveWithdrawalsDeployment(WithdrawalsDeployment memory deployment) public virtual {
        string memory json = "deployment";

        // contract addresses
        serializeProxyElements(json, "withdrawalQueueManager", address(deployment.withdrawalQueueManager));
        serializeProxyElements(json, "ynETHRedemptionAssetsVault", address(deployment.ynETHRedemptionAssetsVault));
        serializeProxyElements(json, "withdrawalsProcessor", address(deployment.withdrawalsProcessor));
        vm.serializeAddress(json, "stakingNodeImplementation", address(deployment.stakingNodeImplementation));
        vm.serializeAddress(json, "implementation-stakingNodesManager", address(deployment.stakingNodesManagerImplementation));
        vm.serializeAddress(json, "implementation-ynETH", address(deployment.ynETHImplementation));


        string memory finalJson = vm.serializeAddress(json, "DEPLOYER", deployer);
        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }

    function verifyDeployment(ContractAddresses contractAddresses, WithdrawalsDeployment memory deployment) internal {
        // Verify WithdrawalQueueManager
        require(address(deployment.withdrawalQueueManager) != address(0), "WithdrawalQueueManager not deployed");
        WithdrawalQueueManager wqm = deployment.withdrawalQueueManager;
        require(wqm.hasRole(wqm.WITHDRAWAL_QUEUE_ADMIN_ROLE(), actors.wallets.YNSecurityCouncil), "ADMIN role not set for WithdrawalQueueManager");
        require(wqm.hasRole(wqm.REDEMPTION_ASSET_WITHDRAWER_ROLE(), actors.wallets.YNDev), "REDEMPTION_ASSET_WITHDRAWER role not set for WithdrawalQueueManager");
        require(wqm.hasRole(wqm.REQUEST_FINALIZER_ROLE(), actors.wallets.YNWithdrawalsETH), "REQUEST_FINALIZER role not set for WithdrawalQueueManager");
        // Assert parameters for WithdrawalQueueManager
        require(address(wqm.redeemableAsset()) == contractAddresses.getChainAddresses(block.chainid).yn.YNETH_ADDRESS, "Redeemable asset not set correctly in WithdrawalQueueManager");
        require(address(wqm.redemptionAssetsVault()) == address(deployment.ynETHRedemptionAssetsVault), "RedemptionAssetsVault not set correctly in WithdrawalQueueManager");
        require(wqm.feeReceiver() == actors.wallets.YNSecurityCouncil, "Fee receiver not set correctly in WithdrawalQueueManager");
        require(wqm.withdrawalFee() == 1000, "Initial withdrawal fee should be 0.1%");
        console.log("\u2705 WithdrawalQueueManager verified");

        // Verify YnETHRedemptionAssetsVault
        require(address(deployment.ynETHRedemptionAssetsVault) != address(0), "YnETHRedemptionAssetsVault not deployed");
        ynETHRedemptionAssetsVault rav = deployment.ynETHRedemptionAssetsVault;
        require(rav.hasRole(rav.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN), "ADMIN role not set for YnETHRedemptionAssetsVault");
        require(rav.hasRole(rav.PAUSER_ROLE(), actors.admin.ADMIN), "PAUSER role not set for YnETHRedemptionAssetsVault");
        require(rav.hasRole(rav.UNPAUSER_ROLE(), actors.admin.ADMIN), "UNPAUSER role not set for YnETHRedemptionAssetsVault");
        require(rav.redeemer() == address(wqm), "Redeemer not set correctly in YnETHRedemptionAssetsVault");
        // Verify ynETH dependency
        require(address(rav.ynETH()) == contractAddresses.getChainAddresses(block.chainid).yn.YNETH_ADDRESS, "ynETH address mismatch in YnETHRedemptionAssetsVault");
        console.log("\u2705 YnETHRedemptionAssetsVault verified");

        // Verify WithdrawalsProcessor
        require(address(deployment.withdrawalsProcessor) != address(0), "WithdrawalsProcessor not deployed");
        WithdrawalsProcessor wp = deployment.withdrawalsProcessor;
        require(wp.hasRole(wp.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN), "ADMIN role not set for WithdrawalsProcessor");
        require(wp.hasRole(wp.WITHDRAWAL_MANAGER_ROLE(), actors.ops.WITHDRAWAL_MANAGER), "WITHDRAWAL_MANAGER role not set for WithdrawalsProcessor");
        require(address(wp.stakingNodesManager()) == contractAddresses.getChainAddresses(block.chainid).yn.STAKING_NODES_MANAGER_ADDRESS, "StakingNodesManager not set correctly in WithdrawalsProcessor");
        console.log("\u2705 WithdrawalsProcessor verified");

        // Verify StakingNodeImplementation
        require(address(deployment.stakingNodeImplementation) != address(0), "StakingNodeImplementation not deployed");
        console.log("\u2705 StakingNodeImplementation verified");

        // Verify StakingNodesManagerImplementation
        require(address(deployment.stakingNodesManagerImplementation) != address(0), "StakingNodesManagerImplementation not deployed");
        console.log("\u2705 StakingNodesManagerImplementation verified");

        // Verify YnETHImplementation
        require(address(deployment.ynETHImplementation) != address(0), "YnETHImplementation not deployed");
        console.log("\u2705 YnETHImplementation verified");

        console.log("All deployments verified successfully.");
    }
}