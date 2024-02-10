import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../src/external/WETH.sol";
import "../../../src/ynETH.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/RewardsReceiver.sol";
import "../../../src/RewardsDistributor.sol";
import "../../../src/interfaces/IStakingNodesManager.sol";
import "../../../src/interfaces/IRewardsDistributor.sol";
import "../ContractAddresses.sol";

// import "../../../src/StakingNode.sol";
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

    uint startingExchangeAdjustmentRate;

    function setUp() public {
        emit log("IntegrationBaseTest setup started");

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
        
        address eigenPodManagerAddress = chainAddresses.EIGENLAYER_EIGENPOD_MANAGER_ADDRESS;
        address delegationManagerAddress = chainAddresses.EIGENLAYER_DELEGATION_MANAGER_ADDRESS;
        address delayedWithdrawalRouterAddress = chainAddresses.EIGENLAYER_DELAYED_WITHDRAWAL_ROUTER_ADDRESS; // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        address strategyManagerAddress = chainAddresses.EIGENLAYER_STRATEGY_MANAGER_ADDRESS;
        address depositContractAddress = chainAddresses.DEPOSIT_2_ADDRESS;

        // Initialize StakingNodesManager with example parameters
        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: address(this),
            stakingAdmin: address(this),
            stakingNodesAdmin: address(this),
            validatorManager: address(this),
            maxNodeCount: 10,
            depositContract: IDepositContract(depositContractAddress), // Assuming an address for the example
            ynETH: IynETH(address(yneth)),
            eigenPodManager: IEigenPodManager(eigenPodManagerAddress),
            delegationManager: IDelegationManager(delegationManagerAddress),
            delayedWithdrawalRouter: IDelayedWithdrawalRouter(delayedWithdrawalRouterAddress),
            strategyManager: IStrategyManager(strategyManagerAddress) // Assuming an address for the example
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);

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
            manager: address(this),
            withdrawer: address(rewardsDistributor)
        });
        executionLayerReceiver.initialize(rewardsReceiverInit);
    }
}

