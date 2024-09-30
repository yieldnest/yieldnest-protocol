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
import {BaseYnETHScript} from "script/BaseYnETHScript.s.sol";
import {ActorAddresses} from "script/Actors.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";


import {console} from "lib/forge-std/src/console.sol";

contract DeployYnETHWithdrawals is BaseYnETHScript {


    struct WithdrawalsDeployment {
        ynETHRedemptionAssetsVault ynETHRedemptionAssetsVault;
        WithdrawalQueueManager withdrawalQueueManager;
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
    ActorAddresses.Actors actors;
    address deployer;

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);
        deployer = publicKey;

        // ynETH.sol ROLES
        actors = getActors();
        
        ContractAddresses contractAddresses = new ContractAddresses();
        IynETH yneth = IynETH(payable(contractAddresses.getChainAddresses(block.chainid).yn.YNETH_ADDRESS));

        // // Apply preprod overrides for DEFAULT_SIGNER
        // if (block.chainid == 17000 && vm.envBool("PREPROD")) { // Holesky testnet or PREPROD environment
        //     address DEFAULT_SIGNER = actors.eoa.DEFAULT_SIGNER;
        //     actors.ops.WITHDRAWAL_MANAGER = DEFAULT_SIGNER;
        //     actors.ops.REDEMPTION_ASSET_WITHDRAWER = DEFAULT_SIGNER;
        //     actors.ops.REQUEST_FINALIZER = DEFAULT_SIGNER;
        //     actors.ops.STAKING_NODES_WITHDRAWER = DEFAULT_SIGNER;
        //     actors.admin.FEE_RECEIVER = DEFAULT_SIGNER;
        //     actors.admin.ADMIN = DEFAULT_SIGNER;
        //     // Override ynETH address for Holesky testnet
        //     yneth = IynETH(payable(0xe8A0fA11735b9C91F5F89340A2E2720e9c9d19fb));
        //     console.log("Overridden ynETH address:", address(yneth));
        //     console.log("Applied preprod overrides for Holesky testnet");
        // }

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);
        

        // Deploy implementation contracts
        StakingNodesManager stakingNodesManagerImplementation = new StakingNodesManager();
        console.log("StakingNodesManager implementation deployed at:", address(stakingNodesManagerImplementation));

        StakingNode stakingNodeImplementation = new StakingNode();
        console.log("StakingNode implementation deployed at:", address(stakingNodeImplementation));

        ynETH ynETHImplementation = new ynETH();
        console.log("ynETH implementation deployed at:", address(ynETHImplementation));

        // deploy ynETHRedemptionAssetsVault
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new ynETHRedemptionAssetsVault()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new WithdrawalQueueManager()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
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
                withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                withdrawalFee: 500, // 0.05%
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            ynETHWithdrawalQueueManager.initialize(managerInit);
        }

        // Verify all the above is deployed correctly.

        // Perform the following permissioned call with DEFAULT_ADMIN ROLE:

        console.log("Parameters for stakingNodesManager.initializeV2:");
        console.log("redemptionAssetsVault:", address(ynETHRedemptionAssetsVaultInstance));
        console.log("withdrawalManager:", actors.ops.WITHDRAWAL_MANAGER);
        console.log("stakingNodesWithdrawer:", actors.ops.STAKING_NODES_WITHDRAWER);


        // Save deployment information
        WithdrawalsDeployment memory deployment = WithdrawalsDeployment({
            ynETHRedemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
            withdrawalQueueManager: ynETHWithdrawalQueueManager,
            stakingNodesManagerImplementation: stakingNodesManagerImplementation,
            stakingNodeImplementation: stakingNodeImplementation,
            ynETHImplementation: ynETH(payable(address(yneth)))
        });

        saveDeployment(deployment);

        console.log("Deployment information saved successfully.");

        // initialize stakingNodesManager withdrawal contracts
        // {
        //     StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
        //         redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
        //         withdrawalManager: actors.ops.WITHDRAWAL_MANAGER,
        //         stakingNodesWithdrawer: actors.ops.STAKING_NODES_WITHDRAWER
        //     });
            
        //     vm.prank(actors.admin.ADMIN);
        //     stakingNodesManager.initializeV2(initParams);
        // }

        vm.stopBroadcast();
    }


    function getDeploymentFile() internal virtual view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/ynETHWithdrawals-", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(WithdrawalsDeployment memory deployment) public virtual {
        string memory json = "deployment";

        // contract addresses
        serializeProxyElements(json, "withdrawalQueueManager", address(deployment.withdrawalQueueManager));
        serializeProxyElements(json, "ynETRewardsRedemptionVault", address(deployment.ynETHRedemptionAssetsVault));
        vm.serializeAddress(json, "stakingNodeImplementation", address(deployment.stakingNodeImplementation));
        vm.serializeAddress(json, "implementation-stakingNodesManager", address(deployment.stakingNodeImplementation));
        vm.serializeAddress(json, "implementation-ynETH", address(deployment.stakingNodeImplementation));


        string memory finalJson = vm.serializeAddress(json, "DEPLOYER", deployer);
        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }
}