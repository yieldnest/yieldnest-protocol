// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IPauserRegistry} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IPauserRegistry.sol";
import {IEigenPodManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IEigenPodManager.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IEigenPod.sol";
import {IStrategyManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IStrategyManager.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IDelayedWithdrawalRouter.sol";
import {IDelegationManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IDelegationManager.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../../src/external/tokens/WETH.sol";
import "../../../src/ynETH.sol";
import "../../../src/ynLSD.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/RewardsReceiver.sol";
import "../../../src/RewardsDistributor.sol";
import "../../../src/ynLSD.sol";
import "../../../src/YieldNestOracle.sol";
import "../../../src/interfaces/IStakingNodesManager.sol";
import "../../../src/interfaces/IRewardsDistributor.sol";
import "../../../scripts/forge/Utils.sol";
import "../../../src/mocks/MockERC20.sol";
import "../../../src/mocks/MockStrategy.sol";
import "../ContractAddresses.sol";
import "forge-std/console.sol";

contract IntegrationBaseTest is Test, Utils {
    address public proxyAdminOwner;
    TransparentUpgradeableProxy public ynethProxy;
    TransparentUpgradeableProxy public stakingNodesManagerProxy;
    TransparentUpgradeableProxy public rewardsDistributorProxy;
    
    ynETH public yneth;
    StakingNodesManager public stakingNodesManager;
    RewardsReceiver public executionLayerReceiver;
    RewardsReceiver public consensusLayerReceiver;

    RewardsDistributor public rewardsDistributor;
    StakingNode public stakingNodeImplementation;
    address payable feeReceiver;

    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IDepositContract public depositContractEth2;

    address public transferEnabledEOA;

    uint public startingExchangeAdjustmentRate;

    ynLSD public ynlsd;
    YieldNestOracle public yieldNestOracle;
    IERC20[] public tokens;
    address[] public assetsAddresses;
    address[] public priceFeeds;
    uint256[] public maxAges;
    IStrategy[] public strategies;

    bytes ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    bytes ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";

    bytes ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 ZERO_DEPOSIT_ROOT = bytes32(0);


    function setUp() public {

        address defaultSigner = vm.addr(1); // Using the default signer address from foundry's vm

        proxyAdminOwner = vm.addr(2);
        feeReceiver = payable(defaultSigner); // Casting the default signer address to payable

        transferEnabledEOA = vm.addr(3);


        startingExchangeAdjustmentRate = 4;

        WETH weth = new WETH();

        // Deploy implementations
        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();
        executionLayerReceiver = new RewardsReceiver();
        consensusLayerReceiver = new RewardsReceiver();
        stakingNodeImplementation = new StakingNode();
        yieldNestOracle = new YieldNestOracle();
        ynlsd = new ynLSD();

        RewardsDistributor rewardsDistributorImplementation = new RewardsDistributor();
        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributorImplementation), address(proxyAdminOwner), "");
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));

        // Deploy proxies
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), address(proxyAdminOwner), "");
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), address(proxyAdminOwner), "");

        yneth = ynETH(payable(ynethProxy));
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));

        // Initialize ynETH with example parameters
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = transferEnabledEOA;
        
        ynETH.Init memory ynethInit = ynETH.Init({
            admin: address(this),
            pauser: address(this),
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            wETH: IWETH(address(weth)),  // Deployed WETH address
            exchangeAdjustmentRate: startingExchangeAdjustmentRate,
            pauseWhitelist: pauseWhitelist
        });
        yneth.initialize(ynethInit);
        
        
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.EIGENLAYER_EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.EIGENLAYER_DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.EIGENLAYER_DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.EIGENLAYER_STRATEGY_MANAGER_ADDRESS);
        depositContractEth2 = IDepositContract(chainAddresses.DEPOSIT_2_ADDRESS);
        // Initialize StakingNodesManager with example parameters
        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: address(this),
            stakingAdmin: address(this),
            stakingNodesAdmin: address(this),
            validatorManager: address(this),
            maxNodeCount: 10,
            depositContract: depositContractEth2,
            ynETH: IynETH(address(yneth)),
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager,
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor))
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);

        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));

        RewardsDistributor.Init memory rewardsDistributorInit = RewardsDistributor.Init({
            admin: address(this),
            executionLayerReceiver: executionLayerReceiver,
            consensusLayerReceiver: consensusLayerReceiver,
            feesReceiver: feeReceiver, // Assuming the contract itself will receive the fees
            ynETH: IynETH(address(yneth))
        });
        rewardsDistributor.initialize(rewardsDistributorInit);

        // Initialize RewardsReceiver with example parameters
        RewardsReceiver.Init memory rewardsReceiverInit = RewardsReceiver.Init({
            admin: address(this),
            withdrawer: address(rewardsDistributor)
        });
        executionLayerReceiver.initialize(rewardsReceiverInit);

        consensusLayerReceiver.initialize(rewardsReceiverInit);
        
        token1 = new MockERC20("Mock1", "MOK");
        token2 = new MockERC20("Mock2", "MOK");
        tokens.push(IERC20(token1));
        tokens.push(IERC20(token2));
        strategies.push(IStrategy(strategy1));
        strategies.push(IStrategy(strategy2));
        
        
        // rETH
        tokens.push(IERC20(chainAddresses.RETH_ADDRESS));
        assetsAddresses.push(chainAddresses.RETH_ADDRESS);
        strategies.push(IStrategy(chainAddresses.RETH_STRATEGY_ADDRESS));
        priceFeeds.push(chainAddresses.RETH_FEED_ADDRESS);
        maxAges.push(uint256(3600));

        // stETH
        tokens.push(IERC20(chainAddresses.STETH_ADDRESS));
        assetsAddresses.push(chainAddresses.STETH_ADDRESS);
        strategies.push(IStrategy(chainAddresses.STETH_STRATEGY_ADDRESS));
        priceFeeds.push(chainAddresses.STETH_FEED_ADDRESS);
        maxAges.push(uint256(3600)); //one hour
        
        YieldNestOracle.Init memory oracleInit = YieldNestOracle.Init({
            assets: assetsAddresses,
            priceFeedAddresses: priceFeeds,
            maxAges: maxAges,
            admin: defaultSigner,
            oracleManager: address(this)
        });
        
       
        ynLSD.Init memory init = ynLSD.Init({
            tokens: tokens,
            strategies: strategies,
            strategyManager: strategyManager,
            oracle: yieldNestOracle,
            exchangeAdjustmentRate: startingExchangeAdjustmentRate
        });

        ynlsd.initialize(init);
        yieldNestOracle.initialize(oracleInit);
        
    }
}

