// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

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
        IRewardsCoordinator rewardsCoordinator;
        IAllocationManager allocationManager;
    }

    EigenLayer public eigenLayer;

    // LSD
    IERC20[] public assets;

    address payable public constant EIGENLAYER_TMELOCK = payable(0xC06Fd4F821eaC1fF1ae8067b36342899b57BAa2d);
    address public constant EIGENLAYER_MULTISIG = 0x461854d84Ee845F905e0eCf6C288DDEEb4A9533F;

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

        chainIds = contractAddresses.getChainIds();

         // execute scheduled transactions for slashing upgrades
        {
            bytes memory payload = hex"6a76120200000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ea00000000000000000000000000000000000000000000000000000000000000d248d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000cc6008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000135dda560e946695d6f155dacafc6f1f25c1f5af000000000000000000000000a396d855d70e1a1ec1a0199adb9845096683b6a2008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000039053d51b77dc0d36036fc1fcc8cb819df8ef37a000000000000000000000000a75112d1df37fa53a431525cd47a7d7facea7e73008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007750d328b314effa365a0402ccfd489b80b0adda000000000000000000000000a505c0116ad65071f0130061f94745b7853220ab008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000858646372cc42e1a627fce94aa7a7033e7cf075a000000000000000000000000ba4b2b8a076851a3044882493c2e36503d50b925005a2a4f2f3c18f09179b6703e63d9edd165909073000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe6000000000000000000000000b132a8dad03a507f1b9d2f467a4936df2161c63e008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000091e677b07f7af907ec9a428aafa9fc14a0d3a3380000000000000000000000009801266cbbbe1e94bb9daf7de8d61528f49cec77008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000acb55c530acdb2849e6d4f36992cd8c9d50ed8f700000000000000000000000090b074ddd680bd06c72e28b09231a0f848205729000ed6703c298d28ae0878d1b28e88ca87f9662fe9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe60000000000000000000000000ec17ef9c00f360db28ca8008684a4796b11e456008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000005e4c39ad7a3e881585e383db9827eb4811f6f6470000000000000000000000001b97d8f963179c0e17e5f3d85cdfd9a31a49bc66008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000093c4b944d05dfe6df7645a86cd2206016c51564d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000001bee69b7dfffa4e2d53c2a2df135c388ad25dcd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000054945180db7943c0ed0fee7edab2bd24620256bc000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000009d7ed45ee2e8fc5482fa2428f15c971e6369011d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000013760f50a9d7377e4f20cb8cf9e4c26586c658ff000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000a4c637e0f704745d182e4d38cab7e7485321d059000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000057ba429517c3473b6d34ca9acd56c0e735b94c02000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000000fe4f44bee93503346a3ac9ee5a26b130a5796d6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007ca911e83dabf90c90dd3de5411a10f1a6112184000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000008ca7a5d6f3acd3a7a8bc468a8cd0fb14b6bd28b6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000ae60d8180437b5c34bb956822ac2710972584473000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000298afb19a105d59e74658c4c334ff360bade6dd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf1780091e677b07f7af907ec9a428aafa9fc14a0d3a33800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024fabc1cbc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000c06fd4f821eac1ff1ae8067b36342899b57baa2d00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000";
            vm.warp(block.timestamp + 11 days);
            vm.prank(EIGENLAYER_MULTISIG);
            TimelockController(EIGENLAYER_TMELOCK).execute(0x369e6F597e22EaB55fFb173C6d9cD234BD699111, 0, payload, bytes32(0), bytes32(0));
        }

        // Setup Protocol
        setupUtils();
        setupYnEigenProxies();
        setupEigenLayer();
        setupTokenStakingNodesManager();
        setupYnEigen();
        setupYieldNestAssets();
        setupYnEigenDepositAdapter();
        
        // Upgrade StakingNode implementation with EL slashing upgrade changes
        // if (_isHolesky()) {
            address newStakingNodeImplementation = address(new TokenStakingNode());
            vm.startPrank(actors.admin.STAKING_ADMIN);
            tokenStakingNodesManager.upgradeTokenStakingNode(newStakingNodeImplementation);
            vm.stopPrank();
        // }
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
        
        if (_isHolesky()) {
            rateProvider = LSDRateProvider(address(new HoleskyLSDRateProvider()));
        } else {
            rateProvider = new LSDRateProvider();
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
        if (_isHolesky()) {
            rateProvider = LSDRateProvider(address(new HoleskyLSDRateProvider()));
        } else {
            rateProvider = new LSDRateProvider();
        }
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
        eigenLayer.rewardsCoordinator = IRewardsCoordinator(chainAddresses.eigenlayer.REWARDS_COORDINATOR_ADDRESS);
        eigenLayer.allocationManager = IAllocationManager(chainAddresses.eigenlayer.ALLOCATION_MANAGER_ADDRESS);
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

        tokenStakingNodesManager.initializeV2(eigenLayer.rewardsCoordinator);
    }

    function setupYieldNestAssets() public {
        uint256 _length = _isHolesky() ? 4 : 5;
        IERC20[] memory lsdAssets = new IERC20[](_length);
        IStrategy[] memory strategies = new IStrategy[](_length);

        // stETH
        // We accept deposits in wstETH, and deploy to the stETH strategy
        lsdAssets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);

        // rETH
        lsdAssets[1] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS);

        // sfrxETH
        // We accept deposits in wsfrxETH, and deploy to the sfrxETH strategy
        lsdAssets[2] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        strategies[2] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);

        // mETH
        // We accept deposits in wmETH, and deploy to the mETH strategy
        lsdAssets[3] = IERC20(chainAddresses.lsd.METH_ADDRESS);
        strategies[3] = IStrategy(chainAddresses.lsdStrategies.METH_STRATEGY_ADDRESS);

        

        if (!_isHolesky()) {
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
        }

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

