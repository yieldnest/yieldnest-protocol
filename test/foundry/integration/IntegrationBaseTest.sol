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

// import "../../../src/StakingNode.sol";
contract IntegrationBaseTest is Test {
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public ynethProxy;
    TransparentUpgradeableProxy public stakingNodesManagerProxy;
    TransparentUpgradeableProxy public rewardsDistributorProxy;
    
    ynETH public yneth;
    StakingNodesManager public stakingNodesManager;
    RewardsReceiver public rewardsReceiver;
    RewardsDistributor public rewardsDistributor;
    StakingNode public stakingNodeImplementation;

    function setUp() public {

        proxyAdmin = new ProxyAdmin(address(this));
        WETH weth = new WETH();

        // Deploy implementations
        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();
        rewardsReceiver = new RewardsReceiver();
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
            wETH: IWETH(address(weth)) // Deployed WETH address
        });
        yneth.initialize(ynethInit);

        // Initialize StakingNodesManager with example parameters
        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: address(this),
            stakingAdmin: address(this),
            stakingNodesAdmin: address(this),
            validatorManager: address(this),
            maxNodeCount: 10,
            depositContract: IDepositContract(address(0)), // Assuming an address for the example
            ynETH: IynETH(address(yneth)),
            eigenPodManager: IEigenPodManager(address(0)), // Assuming an address for the example
            delegationManager: IDelegationManager(address(0)), // Assuming an address for the example
            delayedWithdrawalRouter: IDelayedWithdrawalRouter(address(0)), // Assuming an address for the example
            strategyManager: IStrategyManager(address(0)) // Assuming an address for the example
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);

        // Initialize RewardsReceiver with example parameters
        RewardsReceiver.Init memory rewardsReceiverInit = RewardsReceiver.Init({
            admin: address(this),
            manager: address(this),
            withdrawer: address(stakingNodesManager)
        });
        rewardsReceiver.initialize(rewardsReceiverInit);
    }
}

