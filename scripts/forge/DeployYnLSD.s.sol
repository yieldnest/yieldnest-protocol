import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ynLSD} from "../../../src/ynLSD.sol";
import {StakingNodesManager} from "../../../src/StakingNodesManager.sol";
import {RewardsReceiver} from "../../../src/RewardsReceiver.sol";
import {YieldNestOracle} from "../../../src/YieldNestOracle.sol";
import {LSDStakingNode} from "../../../src/LSDStakingNode.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import "../../src/external/tokens/IWETH.sol";
import "../../test/foundry/ContractAddresses.sol";
import "./BaseScript.s.sol";


contract DeployYnLSD is BaseScript {
    ynLSD public ynlsd;
    YieldNestOracle public yieldNestOracle;
    LSDStakingNode lsdStakingNodeImplementation;

    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IDepositContract public depositContract;
    IWETH public weth;



    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        address ynethAdminAddress = vm.envAddress("YNETH_ADMIN_ADDRESS");
        address pauserAddress = vm.envAddress("PAUSER_ADDRESS");
        address proxyOwnerAddress = vm.envAddress("PROXY_OWNER");

        address rewardsDistributorAdminAddress = vm.envAddress("REWARDS_DISTRIBUTOR_ADMIN_ADDRESS");

        // StakingNodesManager.sol ROLES
        address stakingNodesManagerAdminAddress = vm.envAddress("STAKING_NODES_MANAGER_ADMIN_ADDRESS");
        address stakingAdminAddress = vm.envAddress("STAKING_ADMIN_ADDRESS");
        address stakingNodesAdminAddress = vm.envAddress("STAKING_NODES_ADMIN_ADDRESS");
        address validatorManagerAddress = vm.envAddress("VALIDATOR_MANAGER_ADDRESS");

        address lsdRestakingManager = vm.envAddress("LSD_RESTAKING_MANAGER_ADDRESS");
        address lsdStakingNodeCreatorRole = vm.envAddress("LSD_STAKING_NODE_CREATOR_ADDRESS");
        address yieldNestOracleAdmin = vm.envAddress("YIELDNEST_ORACLE_ADMIN_ADDRESS");

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);


        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);


        address feeReceiver = payable(_broadcaster); // Casting the default signer address to payable


        uint startingExchangeAdjustmentRate = 0;

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        depositContract = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        weth = IWETH(chainAddresses.ethereum.WETH_ADDRESS);

        // Deploy implementations
        ynLSD ynLSDImplementation = new ynLSD();
        TransparentUpgradeableProxy ynLSDProxy = new TransparentUpgradeableProxy(address(ynLSDImplementation), proxyOwnerAddress, "");
        ynlsd = ynLSD(address(ynLSDProxy));

        YieldNestOracle yieldNestOracleImplementation  = new YieldNestOracle();
        TransparentUpgradeableProxy yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracleImplementation), proxyOwnerAddress, "");
        yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));

        lsdStakingNodeImplementation = new LSDStakingNode();

        // Initialize ynLSD with example parameters
        address[] memory lsdPauseWhitelist = new address[](1);
        lsdPauseWhitelist[0] = pauserAddress;

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assets[1] = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);

        ynLSD.Init memory ynlsdInit = ynLSD.Init({
            assets: assets,
            strategies: strategies,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            oracle: yieldNestOracle,
            exchangeAdjustmentRate: startingExchangeAdjustmentRate,
            maxNodeCount: 10,
            admin: ynethAdminAddress,
            pauser: pauserAddress,
            stakingAdmin: stakingAdminAddress,
            lsdRestakingManager: lsdRestakingManager, // Assuming no restaking manager is set initially
            lsdStakingNodeCreatorRole: lsdStakingNodeCreatorRole, // Assuming no staking node creator role is set initially
            pauseWhitelist: lsdPauseWhitelist
        });
        ynlsd.initialize(ynlsdInit);
        uint256[] memory maxAgesArray = new uint256[](assets.length);
        address[] memory priceFeedAddresses = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            maxAgesArray[i] = type(uint256).max;
            if (assets[i] == IERC20(chainAddresses.lsd.RETH_ADDRESS)) {
                priceFeedAddresses[i] = chainAddresses.lsd.RETH_FEED_ADDRESS;
            } else if (assets[i] == IERC20(chainAddresses.lsd.STETH_ADDRESS)) {
                priceFeedAddresses[i] = chainAddresses.lsd.STETH_FEED_ADDRESS;
            }
        }
        address[] memory assetsAddresses = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            assetsAddresses[i] = address(assets[i]);
        }
        YieldNestOracle.Init memory yieldNestOracleInit = YieldNestOracle.Init({
            assets: assetsAddresses,
            priceFeedAddresses: priceFeedAddresses,
            maxAges: maxAgesArray,
            admin: yieldNestOracleAdmin,
            oracleManager: yieldNestOracleAdmin
        });
        yieldNestOracle.initialize(yieldNestOracleInit);
    }
}
