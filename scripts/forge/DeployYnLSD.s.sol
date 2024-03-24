// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ynLSD} from "../../../src/ynLSD.sol";
import {YieldNestOracle} from "../../../src/YieldNestOracle.sol";
import {LSDStakingNode} from "../../../src/LSDStakingNode.sol";
import "../../src/external/tokens/IWETH.sol";
import "../../test/foundry/ContractAddresses.sol";
import "./BaseScript.s.sol";


contract DeployYnLSD is BaseScript {
    ynLSD public ynlsd;
    YieldNestOracle public yieldNestOracle;

    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IDepositContract public depositContract;
    IWETH public weth;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // solhint-disable-next-line no-console
        console.log("Default Signer Address:", _broadcaster);
        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        depositContract = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        weth = IWETH(chainAddresses.ethereum.WETH_ADDRESS);

        // Deploy implementations
        {
            ynLSD ynLSDImplementation = new ynLSD();
            TransparentUpgradeableProxy ynLSDProxy = new TransparentUpgradeableProxy(address(ynLSDImplementation), actors.PROXY_ADMIN_OWNER, "");
            ynlsd = ynLSD(address(ynLSDProxy));
        }

        {
            YieldNestOracle yieldNestOracleImplementation  = new YieldNestOracle();
            TransparentUpgradeableProxy yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracleImplementation), actors.PROXY_ADMIN_OWNER, "");
            yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));
        }

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        assets[1] = IERC20(chainAddresses.lsd.RETH_ADDRESS);


        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);

        {
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
            {
                address[] memory assetsAddresses = new address[](assets.length);
                for (uint256 i = 0; i < assets.length; i++) {
                    assetsAddresses[i] = address(assets[i]);
                }
                YieldNestOracle.Init memory yieldNestOracleInit = YieldNestOracle.Init({
                    assets: assetsAddresses,
                    priceFeedAddresses: priceFeedAddresses,
                    maxAges: maxAgesArray,
                    admin: actors.ORACLE_MANAGER,
                    oracleManager: actors.ORACLE_MANAGER
                });
                yieldNestOracle.initialize(yieldNestOracleInit);
            }


        }
        
        // Initialize ynLSD with example parameters
        {
            address[] memory lsdPauseWhitelist = new address[](1);
            lsdPauseWhitelist[0] = _broadcaster;

            IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
            uint256 mintAmount = 1.0001 ether;
            (bool success, ) = address(stETH).call{value: mintAmount}("");
            require(success, "ETH to stETH mint failed");
            stETH.approve(address(ynlsd), mintAmount);

            ynLSD.Init memory ynlsdInit = ynLSD.Init({
                assets: assets,
                strategies: strategies,
                strategyManager: strategyManager,
                delegationManager: delegationManager,
                oracle: yieldNestOracle,
                maxNodeCount: 10,
                admin: actors.ADMIN,
                pauser: actors.PAUSE_ADMIN,
                stakingAdmin: actors.STAKING_ADMIN,
                lsdRestakingManager: actors.LSD_RESTAKING_MANAGER, // Assuming no restaking manager is set initially
                lsdStakingNodeCreatorRole: actors.STAKING_NODE_CREATOR, // Assuming no staking node creator role is set initially
                pauseWhitelist: lsdPauseWhitelist,
                depositBootstrapper: actors.DEPOSIT_BOOTSTRAPER
            });
            ynlsd.initialize(ynlsdInit);
        }

        {
            LSDStakingNode lsdStakingNodeImplementation = new LSDStakingNode();
            ynlsd.registerLSDStakingNodeImplementationContract(address(lsdStakingNodeImplementation));
            
            ynLSDDeployment memory deployment = ynLSDDeployment({
                ynlsd: ynlsd,
                lsdStakingNodeImplementation: lsdStakingNodeImplementation,
                yieldNestOracle: yieldNestOracle
            });
            
            saveynLSDDeployment(deployment);
        }
        
        vm.stopBroadcast();
    }
}
