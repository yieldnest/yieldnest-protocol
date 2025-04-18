// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPodManager} from "@eigenlayer/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {StrategyManager} from "@eigenlayer/src/contracts/core/StrategyManager.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Utils} from "../../../script/Utils.sol";
import {ActorAddresses} from "../../../script/Actors.sol";
import {ContractAddresses} from "../../../script/ContractAddresses.sol";

import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";

import {TokenStakingNode} from "../../../src/ynEIGEN/TokenStakingNode.sol";
import {ynEigen} from "../../../src/ynEIGEN/ynEigen.sol";
import {AssetRegistry} from "../../../src/ynEIGEN/AssetRegistry.sol";
import {EigenStrategyManager} from "../../../src/ynEIGEN/EigenStrategyManager.sol";
import {LSDRateProvider} from "../../../src/ynEIGEN/LSDRateProvider.sol";
import {ynEigenDepositAdapter} from "../../../src/ynEIGEN/ynEigenDepositAdapter.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestUpgradeUtils} from "test/utils/TestUpgradeUtils.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Test} from "forge-std/Test.sol";

contract ynLSDeScenarioBaseTest is Test, Utils, TestUpgradeUtils {

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    ContractAddresses.ChainIds chainIds;
    ActorAddresses public actorAddresses;
    ActorAddresses.Actors public actors;

    // ynEIGEN Utils
    AssetRegistry public assetRegistry;
    EigenStrategyManager public eigenStrategyManager;
    LSDRateProvider public lsdRateProvider;
    ynEigenDepositAdapter public ynEigenDepositAdapter_;
    TimelockController public timelockController;

    // Staking
    TokenStakingNodesManager public tokenStakingNodesManager;
    TokenStakingNode public tokenStakingNodeImplementation;

    // Assets
    ynEigen public yneigen;

    // ynEIGEN Withdrawals
    RedemptionAssetsVault public redemptionAssetsVault;
    WithdrawalQueueManager public withdrawalQueueManager;
    LSDWrapper public wrapper;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    StrategyManager public strategyManager;

    modifier skipOnHolesky() {
        vm.skip(_isHolesky(), "Impossible to test on Holesky");

        _;
    }
    
    function _isHolesky() internal view returns (bool) {
        return block.chainid == chainIds.holeksy;
    }

    function setUp() public virtual {
        assignContracts(true);
        upgradeTokenStakingNodesManagerTokenStakingNodeEigenStrategyManagerAssetRegistry();
    }

    function assignContracts(bool executeScheduledTransactions) internal {
        uint256 chainId = block.chainid;

        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(chainId);
        chainIds = contractAddresses.getChainIds();
        
        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // Assign Eigenlayer addresses
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        strategyManager = StrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

        // Assign LSD addresses
        // Example: sfrxeth = ISFRXETH(chainAddresses.lsd.SFRXETH_ADDRESS);

        // Assign ynEIGEN addresses
        assetRegistry = AssetRegistry(chainAddresses.ynEigen.ASSET_REGISTRY_ADDRESS);
        eigenStrategyManager = EigenStrategyManager(chainAddresses.ynEigen.EIGEN_STRATEGY_MANAGER_ADDRESS);
        lsdRateProvider = LSDRateProvider(chainAddresses.ynEigen.LSD_RATE_PROVIDER_ADDRESS);
        ynEigenDepositAdapter_ = ynEigenDepositAdapter(chainAddresses.ynEigen.YNEIGEN_DEPOSIT_ADAPTER_ADDRESS);
        tokenStakingNodesManager = TokenStakingNodesManager(chainAddresses.ynEigen.TOKEN_STAKING_NODES_MANAGER_ADDRESS);
        yneigen = ynEigen(chainAddresses.ynEigen.YNEIGEN_ADDRESS);
        timelockController = TimelockController(payable(chainAddresses.ynEigen.TIMELOCK_CONTROLLER_ADDRESS));
        redemptionAssetsVault = RedemptionAssetsVault(chainAddresses.ynEigen.REDEMPTION_ASSETS_VAULT_ADDRESS);
        withdrawalQueueManager = WithdrawalQueueManager(chainAddresses.ynEigen.WITHDRAWAL_QUEUE_MANAGER_ADDRESS);
        wrapper = LSDWrapper(chainAddresses.ynEigen.WRAPPER);

        // execute scheduled transactions for slashing upgrades
        if (false) {
            // Update token staking nodes balances for all assets before slashing upgrade when its possible

            TestUpgradeUtils.executeEigenlayerSlashingUpgrade();
        }
    }

    function updateTokenStakingNodesBalancesForAllAssets() internal {
        // Update token staking nodes balances for all assets
        IERC20[] memory assets = yneigen.assetRegistry().getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            eigenStrategyManager.updateTokenStakingNodesBalances(assets[i]);
        }
    }

    function upgradeTokenStakingNodesManagerTokenStakingNodeEigenStrategyManagerAssetRegistry() internal {

        uint256 totalAssetsBefore = yneigen.totalAssets();
        // Deploy new TokenStakingNode implementation
        // address newTokenStakingNodeImpl = address(new TokenStakingNode());
        // address newTokenStakingNodesManagerImpl = address(new TokenStakingNodesManager());
        address newTokenStakingNodeImpl = 0x74ff5C9F93080d20D505ffa3cc291f5bFaD43655;
        address newTokenStakingNodesManagerImpl = 0x6Fbd79BbF9dA002c33F94D0a372F9756756adb2c;

        vm.prank(address(timelockController));
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenStakingNodesManager)),
            newTokenStakingNodesManagerImpl,
            ""
        );


        // Register new implementation
        vm.prank(address(timelockController));
        tokenStakingNodesManager.upgradeTokenStakingNode(newTokenStakingNodeImpl);

        {
            // Deploy new EigenStrategyManager implementation
            // address newEigenStrategyManagerImpl = address(new EigenStrategyManager());
            address newEigenStrategyManagerImpl = 0xAB0153A53Db6e12c0A86D1404B509BC647333E79;
            
            // Get the proxy admin for the EigenStrategyManager
            address proxyAdmin = getTransparentUpgradeableProxyAdminAddress(address(eigenStrategyManager));
            
            // Upgrade the EigenStrategyManager implementation through the proxy admin
            vm.prank(address(timelockController));
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(address(eigenStrategyManager)),
                newEigenStrategyManagerImpl,
                ""
            );
        }

        {
            // Deploy new AssetRegistry implementation
            // address newAssetRegistryImpl = address(new AssetRegistry());
            address newAssetRegistryImpl = 0x031AE4a8a09b1779DBF69828356945fdf59D6879;
            // Get the proxy admin for the AssetRegistry
            address proxyAdmin = getTransparentUpgradeableProxyAdminAddress(address(assetRegistry));
            
            // Upgrade the AssetRegistry implementation through the proxy admin
            vm.prank(address(timelockController));
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(address(assetRegistry)),
                newAssetRegistryImpl,
                ""
            );
        }

        {
            // Synchronize all token staking nodes and update their balances
            ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
            
            // Call synchronizeNodesAndUpdateBalances with the array of all nodes
            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        }

        // 3632658160216128530 is an increase after synchronization 
        assertEq(yneigen.totalAssets(), totalAssetsBefore + 3632658160216128530, "Total assets changed after upgrade");
    }
}