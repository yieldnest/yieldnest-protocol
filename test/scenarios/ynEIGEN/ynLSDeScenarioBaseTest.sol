// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPodManager} from "@eigenlayer/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Utils} from "../../../script/Utils.sol";
import {ActorAddresses} from "../../../script/Actors.sol";
import {ContractAddresses} from "../../../script/ContractAddresses.sol";

import {TokenStakingNodesManager} from "../../../src/ynEIGEN/TokenStakingNodesManager.sol";
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


import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


import {Test} from "forge-std/Test.sol";

contract ynLSDeScenarioBaseTest is Test, Utils {

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
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
    IStrategyManager public strategyManager;

    function setUp() public virtual {
        assignContracts();
        upgradeTokenStakingNodesManagerAndTokenStakingNode();
    }

    function assignContracts() internal {
        uint256 chainId = block.chainid;

        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(chainId);

        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // Assign Eigenlayer addresses
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

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

    }

    function updateTokenStakingNodesBalancesForAllAssets() internal {
        // Update token staking nodes balances for all assets
        IERC20[] memory assets = yneigen.assetRegistry().getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            eigenStrategyManager.updateTokenStakingNodesBalances(assets[i]);
        }
    }

    function upgradeTokenStakingNodesManagerAndTokenStakingNode() internal {
        // Deploy new TokenStakingNode implementation
        address newTokenStakingNodeImpl = address(new TokenStakingNode());

        // Upgrade TokenStakingNodesManager
        bytes memory initializeV3Data = abi.encodeWithSelector(
            tokenStakingNodesManager.initializeV2.selector,
            chainAddresses.eigenlayer.REWARDS_COORDINATOR_ADDRESS
        );

        address newTokenStakingNodesManagerImpl = address(new TokenStakingNodesManager());

        vm.prank(address(timelockController));
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(tokenStakingNodesManager)),
            newTokenStakingNodesManagerImpl,
            initializeV3Data
        );

        // Register new implementation
        vm.prank(address(timelockController));
        tokenStakingNodesManager.upgradeTokenStakingNode(newTokenStakingNodeImpl);
    }
}