// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {Test} from "forge-std/Test.sol";
import {ynETH} from "src/ynETH.sol";
import {ynViewer} from "src/ynViewer.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {StakingNode} from "src/StakingNode.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";
import {HoleskyLSDRateProvider} from "src/testnet/HoleksyLSDRateProvider.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";


contract ynEigenIntegrationBaseTest is Test, Utils {

    // State
    bytes constant ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    bytes constant ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
    bytes constant TWO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002";
    bytes constant  ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 constant ZERO_DEPOSIT_ROOT = bytes32(0);

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    ContractAddresses.ChainIds chainIds;
    ActorAddresses public actorAddresses;
    ActorAddresses.Actors public actors;

    // Staking
    TokenStakingNodesManager public tokenStakingNodesManager;
    TokenStakingNode public tokenStakingNodeImplementation;

    // Assets
    ynEigen public ynEigenToken;
    AssetRegistry public assetRegistry;
    LSDRateProvider public rateProvider;
    ynEigenDepositAdapter public ynEigenDepositAdapterInstance;
    RedemptionAssetsVault public redemptionAssetsVault;
    WithdrawalQueueManager public withdrawalQueueManager;
    LSDWrapper public wrapper;

    // Strategy
    EigenStrategyManager public eigenStrategyManager;

    // Eigen
    struct EigenLayer {
        IEigenPodManager eigenPodManager;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
    }

    EigenLayer public eigenLayer;

    // LSD
    IERC20[] public assets;

    modifier skipOnHolesky() {
        vm.skip(_isHolesky(), "Impossible to test on Holesky");

        _;
    }
    
     function _isHolesky() internal view returns (bool) {
        return block.chainid == chainIds.holeksy;
    }

    function setUp() public virtual {


        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();

        (uint256 mainnet, uint256 holeksy) = contractAddresses.chainIds();
        chainIds = ContractAddresses.ChainIds(mainnet, holeksy);

        // Setup Protocol
        setupUtils();
        setupYnEigenProxies();
        setupEigenLayer();
        setupTokenStakingNodesManager();
        setupYnEigen();
        setupYieldNestAssets();
        setupYnEigenDepositAdapter();
    }

    function setupYnEigenProxies() public {
        TransparentUpgradeableProxy ynEigenProxy;
        TransparentUpgradeableProxy eigenStrategyManagerProxy;
        TransparentUpgradeableProxy tokenStakingNodesManagerProxy;
        TransparentUpgradeableProxy assetRegistryProxy;
        TransparentUpgradeableProxy rateProviderProxy;
        TransparentUpgradeableProxy ynEigenDepositAdapterProxy;

        ynEigenToken = new ynEigen();
        eigenStrategyManager = new EigenStrategyManager();
        tokenStakingNodesManager = new TokenStakingNodesManager();
        assetRegistry = new AssetRegistry();
        
        if (block.chainid == chainIds.mainnet) {
            rateProvider = new LSDRateProvider();
        } else if (_isHolesky()) {
            rateProvider = LSDRateProvider(address(new HoleskyLSDRateProvider()));
        }
        ynEigenDepositAdapterInstance = new ynEigenDepositAdapter();

        ynEigenProxy = new TransparentUpgradeableProxy(address(ynEigenToken), actors.admin.PROXY_ADMIN_OWNER, "");
        eigenStrategyManagerProxy = new TransparentUpgradeableProxy(address(eigenStrategyManager), actors.admin.PROXY_ADMIN_OWNER, "");
        tokenStakingNodesManagerProxy = new TransparentUpgradeableProxy(address(tokenStakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");
        assetRegistryProxy = new TransparentUpgradeableProxy(address(assetRegistry), actors.admin.PROXY_ADMIN_OWNER, "");
        rateProviderProxy = new TransparentUpgradeableProxy(address(rateProvider), actors.admin.PROXY_ADMIN_OWNER, "");
        ynEigenDepositAdapterProxy = new TransparentUpgradeableProxy(address(ynEigenDepositAdapterInstance), actors.admin.PROXY_ADMIN_OWNER, "");

        // Wrapping proxies with their respective interfaces
        ynEigenToken = ynEigen(payable(ynEigenProxy));
        eigenStrategyManager = EigenStrategyManager(payable(eigenStrategyManagerProxy));
        tokenStakingNodesManager = TokenStakingNodesManager(payable(tokenStakingNodesManagerProxy));
        assetRegistry = AssetRegistry(payable(assetRegistryProxy));
        
        rateProvider = LSDRateProvider(payable(rateProviderProxy));
        
        ynEigenDepositAdapterInstance = ynEigenDepositAdapter(payable(ynEigenDepositAdapterProxy));

        // Re-deploying ynEigen and creating its proxy again
        ynEigenToken = new ynEigen();
        ynEigenProxy = new TransparentUpgradeableProxy(address(ynEigenToken), actors.admin.PROXY_ADMIN_OWNER, "");
        ynEigenToken = ynEigen(payable(ynEigenProxy));

        // Re-deploying EigenStrategyManager and creating its proxy again
        eigenStrategyManager = new EigenStrategyManager();
        eigenStrategyManagerProxy = new TransparentUpgradeableProxy(address(eigenStrategyManager), actors.admin.PROXY_ADMIN_OWNER, "");
        eigenStrategyManager = EigenStrategyManager(payable(eigenStrategyManagerProxy));

        // Re-deploying TokenStakingNodesManager and creating its proxy again
        tokenStakingNodesManager = new TokenStakingNodesManager();
        tokenStakingNodesManagerProxy = new TransparentUpgradeableProxy(address(tokenStakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");
        tokenStakingNodesManager = TokenStakingNodesManager(payable(tokenStakingNodesManagerProxy));

        // Re-deploying AssetRegistry and creating its proxy again
        assetRegistry = new AssetRegistry();
        assetRegistryProxy = new TransparentUpgradeableProxy(address(assetRegistry), actors.admin.PROXY_ADMIN_OWNER, "");
        assetRegistry = AssetRegistry(payable(assetRegistryProxy));

        // Re-deploying LSDRateProvider and creating its proxy again
        rateProvider = new LSDRateProvider();
        rateProviderProxy = new TransparentUpgradeableProxy(address(rateProvider), actors.admin.PROXY_ADMIN_OWNER, "");
        rateProvider = LSDRateProvider(payable(rateProviderProxy));

        // Re-deploying ynEigenDepositAdapter and creating its proxy again
        ynEigenDepositAdapterInstance = new ynEigenDepositAdapter();
        ynEigenDepositAdapterProxy = new TransparentUpgradeableProxy(address(ynEigenDepositAdapterInstance), actors.admin.PROXY_ADMIN_OWNER, "");
        ynEigenDepositAdapterInstance = ynEigenDepositAdapter(payable(ynEigenDepositAdapterProxy));
    }

    function setupUtils() public {
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);
    }

    function setupEigenLayer() public {
        eigenLayer.strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        eigenLayer.eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        eigenLayer.delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
    }

    function setupYnEigen() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;

        ynEigen.Init memory ynEigenInit = ynEigen.Init({
            name: "Eigenlayer YieldNest LSD",
            symbol: "ynLSDe",
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            yieldNestStrategyManager: address(eigenStrategyManager),
            assetRegistry: IAssetRegistry(address(assetRegistry)),
            pauseWhitelist: pauseWhitelist
        });

        ynEigenToken.initialize(ynEigenInit);
    }

    function setupTokenStakingNodesManager() public {
        tokenStakingNodeImplementation = new TokenStakingNode();

        TokenStakingNodesManager.Init memory tokenStakingNodesManagerInit = TokenStakingNodesManager.Init({
            strategyManager: eigenLayer.strategyManager,
            delegationManager: eigenLayer.delegationManager,
            yieldNestStrategyManager: address(eigenStrategyManager),
            maxNodeCount: 10,
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingAdmin: actors.admin.STAKING_ADMIN,
            tokenStakingNodeOperator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
            tokenStakingNodeCreatorRole: actors.ops.STAKING_NODE_CREATOR,
            tokenStakingNodesDelegator: actors.admin.STAKING_NODES_DELEGATOR
        });

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        tokenStakingNodesManager.initialize(tokenStakingNodesManagerInit);
        vm.prank(actors.admin.STAKING_ADMIN); // TokenStakingNodesManager is the only contract that can register a staking node implementation contract
        tokenStakingNodesManager.registerTokenStakingNode(address(tokenStakingNodeImplementation));
    }

    function setupYieldNestAssets() public {
        IERC20[] memory lsdAssets = new IERC20[](5);
        IStrategy[] memory strategies = new IStrategy[](5);

        // stETH
        // We accept deposits in wstETH, and deploy to the stETH strategy
        lsdAssets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);

        // rETH
        lsdAssets[1] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS);

        // oETH
        // We accept deposits in woETH, and deploy to the oETH strategy
        lsdAssets[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        strategies[2] = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);

        // sfrxETH
        // We accept deposits in wsfrxETH, and deploy to the sfrxETH strategy
        lsdAssets[3] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        strategies[3] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);

        // mETH
        // We accept deposits in wmETH, and deploy to the mETH strategy
        lsdAssets[4] = IERC20(chainAddresses.lsd.METH_ADDRESS);
        strategies[4] = IStrategy(chainAddresses.lsdStrategies.METH_STRATEGY_ADDRESS);

        for (uint i = 0; i < lsdAssets.length; i++) {
            assets.push(lsdAssets[i]);
        }

        EigenStrategyManager.Init memory eigenStrategyManagerInit = EigenStrategyManager.Init({
            assets: lsdAssets,
            strategies: strategies,
            ynEigen: IynEigen(address(ynEigenToken)),
            strategyManager: IStrategyManager(address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS)),
            delegationManager: IDelegationManager(address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS)),
            tokenStakingNodesManager: ITokenStakingNodesManager(address(tokenStakingNodesManager)),
            admin: actors.admin.ADMIN,
            strategyController: actors.ops.STRATEGY_CONTROLLER,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            strategyAdmin: actors.admin.EIGEN_STRATEGY_ADMIN,
            wstETH: IwstETH(chainAddresses.lsd.WSTETH_ADDRESS),
            woETH: IERC4626(chainAddresses.lsd.WOETH_ADDRESS)
        });
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        eigenStrategyManager.initialize(eigenStrategyManagerInit);

        AssetRegistry.Init memory assetRegistryInit = AssetRegistry.Init({
            assets: lsdAssets,
            rateProvider: IRateProvider(address(rateProvider)),
            yieldNestStrategyManager: IYieldNestStrategyManager(address(eigenStrategyManager)),
            ynEigen: IynEigen(address(ynEigenToken)),
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            assetManagerRole: actors.admin.ASSET_MANAGER
        });
        assetRegistry.initialize(assetRegistryInit);

        // deploy RedemptionAssetsVault
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new RedemptionAssetsVault()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            redemptionAssetsVault = RedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new WithdrawalQueueManager()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            withdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
        }

        // deploy wrapper
        {
            // call `initialize` on LSDWrapper
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(
                    new LSDWrapper(
                        chainAddresses.lsd.WSTETH_ADDRESS,
                        chainAddresses.lsd.WOETH_ADDRESS,
                        chainAddresses.lsd.OETH_ADDRESS,
                        chainAddresses.lsd.STETH_ADDRESS)
                    ),
                actors.admin.PROXY_ADMIN_OWNER,
                abi.encodeWithSignature("initialize()")
            );
            wrapper = LSDWrapper(address(_proxy));
        }

        // initialize eigenStrategyManager
        {
            eigenStrategyManager.initializeV2(address(redemptionAssetsVault), address(wrapper), actors.ops.WITHDRAWAL_MANAGER);
        }

        // initialize RedemptionAssetsVault
        {
            RedemptionAssetsVault.Init memory _init = RedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(withdrawalQueueManager),
                ynEigen: ynEigenToken,
                assetRegistry: assetRegistry
            });
            redemptionAssetsVault.initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
                name: "ynLSDe Withdrawal Manager",
                symbol: "ynLSDeWM",
                redeemableAsset: IRedeemableAsset(address(ynEigenToken)),
                redemptionAssetsVault: redemptionAssetsVault,
                admin: actors.admin.PROXY_ADMIN_OWNER,
                withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                // withdrawalFee: 500, // 0.05%
                withdrawalFee: 0,
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            withdrawalQueueManager.initialize(_init);
        }
    }

        function setupYnEigenDepositAdapter() public {
            ynEigenDepositAdapter.Init memory ynEigenDepositAdapterInit = ynEigenDepositAdapter.Init({
                ynEigen: address(ynEigenToken),
                wstETH: chainAddresses.lsd.WSTETH_ADDRESS,
                woETH: chainAddresses.lsd.WOETH_ADDRESS,
                admin: actors.admin.ADMIN
            });
            vm.prank(actors.admin.PROXY_ADMIN_OWNER);
            ynEigenDepositAdapterInstance.initialize(ynEigenDepositAdapterInit);
            ynEigenDepositAdapterInstance.initializeV2(address(wrapper));
        }
}

