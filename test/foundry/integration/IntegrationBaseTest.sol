
import {IPauserRegistry} from "../../../src/interfaces/eigenlayer-init-mainnet/IPauserRegistry.sol";
import {IEigenPodManager} from "../../../src/interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import {IEigenPod} from "../../../src/interfaces/eigenlayer-init-mainnet/IEigenPod.sol";
import {IStrategyManager} from "../../../src/interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import {IDelayedWithdrawalRouter} from "../../../src/interfaces/eigenlayer-init-mainnet/IDelayedWithdrawalRouter.sol";
import {IDelegationManager} from "../../../src/interfaces/eigenlayer-init-mainnet/IDelegationManager.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../src/external/WETH.sol";
import "../../../src/ynETH.sol";
import "../../../src/ynLSD.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/RewardsReceiver.sol";
import "../../../src/RewardsDistributor.sol";
import "../../../src/ynLSD.sol";
import "../../../src/YieldNestOracle.sol";
import "../../../src/interfaces/IStakingNodesManager.sol";
import "../../../src/interfaces/IRewardsDistributor.sol";
import "../../../src/mocks/MockERC20.sol";
import "../../../src/mocks/MockStrategy.sol";
import "../ContractAddresses.sol";
import "forge-std/console.sol";

contract IntegrationBaseTest is Test {
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public ynethProxy;
    TransparentUpgradeableProxy public stakingNodesManagerProxy;
    TransparentUpgradeableProxy public rewardsDistributorProxy;
    
    ynETH public yneth;
    StakingNodesManager public stakingNodesManager;
    RewardsReceiver public executionLayerReceiver;
    RewardsDistributor public rewardsDistributor;
    StakingNode public stakingNodeImplementation;
    address payable feeReceiver;

    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IDepositContract public depositContract;

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
        feeReceiver = payable(defaultSigner); // Casting the default signer address to payable


        startingExchangeAdjustmentRate = 4;

        proxyAdmin = new ProxyAdmin(address(this));
        WETH weth = new WETH();

        // Deploy implementations
        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();
        executionLayerReceiver = new RewardsReceiver();
        stakingNodeImplementation = new StakingNode();
        yieldNestOracle = new YieldNestOracle();
        ynlsd = new ynLSD();

        RewardsDistributor rewardsDistributorImplementation = new RewardsDistributor();
        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributorImplementation), address(proxyAdmin), "");
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));

        // Deploy proxies
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), address(proxyAdmin), "");
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), address(proxyAdmin), "");

        yneth = ynETH(payable(ynethProxy));
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));

        // Initialize ynETH with example parameters
        ynETH.Init memory ynethInit = ynETH.Init({
            admin: address(this),
            pauser: address(this),
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            wETH: IWETH(address(weth)),  // Deployed WETH address
            exchangeAdjustmentRate: startingExchangeAdjustmentRate
        });
        yneth.initialize(ynethInit);
        
        
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.EIGENLAYER_EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.EIGENLAYER_DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.EIGENLAYER_DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.EIGENLAYER_STRATEGY_MANAGER_ADDRESS);
        depositContract = IDepositContract(chainAddresses.DEPOSIT_2_ADDRESS);
        // Initialize StakingNodesManager with example parameters
        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: address(this),
            stakingAdmin: address(this),
            stakingNodesAdmin: address(this),
            validatorManager: address(this),
            maxNodeCount: 10,
            depositContract: depositContract,
            ynETH: IynETH(address(yneth)),
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);

        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));

        RewardsDistributor.Init memory rewardsDistributorInit = RewardsDistributor.Init({
            admin: address(this),
            executionLayerReceiver: executionLayerReceiver,
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

        
        
        // rETH
        tokens.push(IERC20(chainAddresses.RETH_ADDRESS));
        assetsAddresses.push(chainAddresses.RETH_ADDRESS);
        strategies.push(IStrategy(chainAddresses.RETH_STRATEGY_ADDRESS));
        priceFeeds.push(chainAddresses.RETH_FEED_ADDRESS);
        maxAges.push(uint256(86400));

        // stETH
        tokens.push(IERC20(chainAddresses.STETH_ADDRESS));
        assetsAddresses.push(chainAddresses.STETH_ADDRESS);
        strategies.push(IStrategy(chainAddresses.STETH_STRATEGY_ADDRESS));
        priceFeeds.push(chainAddresses.STETH_FEED_ADDRESS);
        maxAges.push(uint256(86400)); //one hour
        
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

