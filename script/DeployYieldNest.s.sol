// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "src/StakingNodesManager.sol";
import "src/RewardsReceiver.sol";
import "src/RewardsDistributor.sol";
import "src/ynETH.sol";
import "src/interfaces/IStakingNode.sol";
import "src/external/ethereum/IDepositContract.sol";
import "src/interfaces/IRewardsDistributor.sol";
import "src/external/tokens/IWETH.sol";
import "script/ContractAddresses.sol";
import "script/BaseScript.s.sol";
import "src/YieldNestOracle.sol";
import "src/ynLSD.sol";


contract DeployYieldNest is BaseScript {

    TransparentUpgradeableProxy public ynethProxy;
    TransparentUpgradeableProxy public stakingNodesManagerProxy;
    TransparentUpgradeableProxy public rewardsDistributorProxy;
    TransparentUpgradeableProxy public yieldNestOracleProxy;
    TransparentUpgradeableProxy public ynLSDProxy;
    TransparentUpgradeableProxy public executionLayerReceiverProxy;
    TransparentUpgradeableProxy public consensusLayerReceiverProxy;

    ynETH public yneth;
    StakingNodesManager public stakingNodesManager;
    RewardsReceiver public executionLayerReceiver;
    RewardsReceiver public consensusLayerReceiver; // Added consensusLayerReceiver
    RewardsDistributor public rewardsDistributor;
    StakingNode public stakingNodeImplementation;
    YieldNestOracle public yieldNestOracle;
    ynLSD public ynlsd;
    address payable feeReceiver;

    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IDepositContract public depositContract;
    IWETH public weth;

    ActorAddresses.Actors actors;

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        feeReceiver = payable(_broadcaster); // Casting the default signer address to payable

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        depositContract = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        weth = IWETH(chainAddresses.ethereum.WETH_ADDRESS);

        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();

        RewardsReceiver executionLayerReceiverImplementation = new RewardsReceiver();
        RewardsReceiver consensusLayerReceiverImplementation = new RewardsReceiver();

        executionLayerReceiverProxy = new TransparentUpgradeableProxy(address(executionLayerReceiverImplementation), actors.PROXY_ADMIN_OWNER, "");
        consensusLayerReceiverProxy = new TransparentUpgradeableProxy(address(consensusLayerReceiverImplementation), actors.PROXY_ADMIN_OWNER, "");

        executionLayerReceiver = RewardsReceiver(payable(executionLayerReceiverProxy));
        consensusLayerReceiver = RewardsReceiver(payable(consensusLayerReceiverProxy));

        stakingNodeImplementation = new StakingNode();
        yieldNestOracle = new YieldNestOracle();
        ynlsd = new ynLSD();

        RewardsDistributor rewardsDistributorImplementation = new RewardsDistributor();
        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributorImplementation), actors.PROXY_ADMIN_OWNER, "");
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));

        YieldNestOracle yieldNestOracleImplementation  = new YieldNestOracle();
        yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracleImplementation), actors.PROXY_ADMIN_OWNER, "");
        yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));

        ynLSD ynLSDImplementation = new ynLSD();
        ynLSDProxy = new TransparentUpgradeableProxy(address(ynLSDImplementation), actors.PROXY_ADMIN_OWNER, "");
        ynlsd = ynLSD(address(ynLSDProxy));

        // Deploy proxies
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.PROXY_ADMIN_OWNER, "");
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.PROXY_ADMIN_OWNER, "");

        yneth = ynETH(payable(ynethProxy));
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));
    
        // Initialize ynETH with example parameters
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.PAUSE_ADMIN;

        ynETH.Init memory ynethInit = ynETH.Init({
            admin: actors.ADMIN,
            pauser: actors.PAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });
        yneth.initialize(ynethInit);

        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: actors.DEFAULT_SIGNER, // change at end of script
            stakingAdmin: actors.DEFAULT_SIGNER, // change at end of script
            stakingNodesAdmin: actors.STAKING_NODES_ADMIN,
            validatorManager: actors.VALIDATOR_MANAGER,
            stakingNodeCreatorRole: actors.STAKING_NODE_CREATOR,
            pauser: actors.PAUSE_ADMIN,
            maxNodeCount: 10,
            ynETH: IynETH(address(yneth)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            depositContract: depositContract,
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);

        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));

        RewardsDistributor.Init memory rewardsDistributorInit = RewardsDistributor.Init({
            admin: actors.ADMIN,
            executionLayerReceiver: executionLayerReceiver,
            consensusLayerReceiver: consensusLayerReceiver, // Adding consensusLayerReceiver to the initialization
            feesReceiver: feeReceiver, // Assuming the contract itself will receive the fees
            ynETH: IynETH(address(yneth))
        });
        rewardsDistributor.initialize(rewardsDistributorInit);

        // Initialize RewardsReceiver with example parameters
        RewardsReceiver.Init memory rewardsReceiverInit = RewardsReceiver.Init({
            admin: actors.ADMIN,
            withdrawer: address(rewardsDistributor)
        });
        executionLayerReceiver.initialize(rewardsReceiverInit);
        consensusLayerReceiver.initialize(rewardsReceiverInit); // Initializing consensusLayerReceiver

        // set these roles after deployment
        stakingNodesManager.grantRole(stakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.ADMIN);
        stakingNodesManager.grantRole(stakingNodesManager.STAKING_ADMIN_ROLE(), actors.STAKING_ADMIN);

        vm.stopBroadcast();

        Deployment memory deployment = Deployment({
            ynETH: yneth,
            stakingNodesManager: stakingNodesManager,
            executionLayerReceiver: executionLayerReceiver,
            consensusLayerReceiver: consensusLayerReceiver, // Adding consensusLayerReceiver to the deployment
            rewardsDistributor: rewardsDistributor,
            stakingNodeImplementation: stakingNodeImplementation
        });
        
        saveDeployment(deployment);

    }
}

