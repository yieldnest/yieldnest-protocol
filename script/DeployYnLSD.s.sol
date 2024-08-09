// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IDelayedWithdrawalRouter} from "src/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IWETH} from "src/external/tokens/IWETH.sol";

import {ynLSD} from "src/ynLSD.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {LSDStakingNode} from "src/LSDStakingNode.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {console} from "lib/forge-std/src/console.sol";

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
            TransparentUpgradeableProxy ynLSDProxy = new TransparentUpgradeableProxy(address(ynLSDImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            ynlsd = ynLSD(address(ynLSDProxy));
        }

        {
            YieldNestOracle yieldNestOracleImplementation  = new YieldNestOracle();
            TransparentUpgradeableProxy yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracleImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));
        }

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assets[1] = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);
        // Initialize ynLSD with example parameters
        {
            address[] memory lsdPauseWhitelist = new address[](1);
            lsdPauseWhitelist[0] = _broadcaster;

            ynLSD.Init memory ynlsdInit = ynLSD.Init({
                assets: assets,
                strategies: strategies,
                strategyManager: strategyManager,
                delegationManager: delegationManager,
                oracle: yieldNestOracle,
                maxNodeCount: 10,
                admin: actors.admin.ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                stakingAdmin: actors.admin.STAKING_ADMIN,
                lsdRestakingManager: actors.ops.LSD_RESTAKING_MANAGER,
                lsdStakingNodeCreatorRole: actors.ops.STAKING_NODE_CREATOR,
                pauseWhitelist: lsdPauseWhitelist,
                depositBootstrapper: actors.eoa.DEPOSIT_BOOTSTRAPPER
            });
            ynlsd.initialize(ynlsdInit);
        }

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
                admin: actors.admin.ORACLE_ADMIN,
                oracleManager: actors.admin.ORACLE_ADMIN
            });
            yieldNestOracle.initialize(yieldNestOracleInit);
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
    }
}
