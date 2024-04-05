// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {ynLSD} from "src/ynLSD.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {MockYnETHERC4626} from "test/mocks/MockYnETHERC4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "src/external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";

contract UpgradesTest is IntegrationBaseTest {

    function testUpgradeYnETH() public {
        address newImplementation = address(new ynETH()); 
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");

        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        assertEq(currentImplementation, newImplementation);
    }

    function testUpgradeStakingNodesManager() public {
        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        
        address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerImpl);
    }

    function testUpgradeRewardsDistributor() public {
        address newRewardsDistributorImpl = address(new RewardsDistributor());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        
        address currentRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        assertEq(currentRewardsDistributorImpl, newRewardsDistributorImpl);
    }

    function testUpgradeYnLSD() public {
        address newYnLSDImpl = address(new ynLSD());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newYnLSDImpl, "");
        
        address currentYnLSDImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynlsd));
        assertEq(currentYnLSDImpl, newYnLSDImpl);
    }

    function testUpgradeYieldNestOracle() public {
        address newYieldNestOracleImpl = address(new YieldNestOracle());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yieldNestOracle))).upgradeAndCall(ITransparentUpgradeableProxy(address(yieldNestOracle)), newYieldNestOracleImpl, "");
        
        address currentYieldNestOracleImpl = getTransparentUpgradeableProxyImplementationAddress(address(yieldNestOracle));
        assertEq(currentYieldNestOracleImpl, newYieldNestOracleImpl);
    }

    function testUpgradeStakingNodesManagerToV2AndReinit() public {
        TestStakingNodesManagerV2.ReInit memory reInit = TestStakingNodesManagerV2.ReInit({
            newV2Value: 42
        });

        address newStakingNodesManagerV2Impl = address(new TestStakingNodesManagerV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(
                ITransparentUpgradeableProxy(address(stakingNodesManager)),
                newStakingNodesManagerV2Impl,
                abi.encodeWithSelector(TestStakingNodesManagerV2.initializeV2.selector, reInit)
            );

        address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerV2Impl);

        TestStakingNodesManagerV2 upgradedStakingNodesManager = TestStakingNodesManagerV2(payable(stakingNodesManager));
        assertEq(upgradedStakingNodesManager.newV2Value(), 42, "Reinit value not set correctly");
    }

    function testUpgradeabilityofYnETHToAnERC4626() public {

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        vm.prank(address(this));
        yneth.depositETH{value: depositAmount}(address(this));

        uint256 finalTotalAssets = yneth.totalAssets();
        uint256 finalTotalSupply = yneth.totalSupply();
        // Save original ynETH state
        IStakingNodesManager originalStakingNodesManager = yneth.stakingNodesManager();
        IRewardsDistributor originalRewardsDistributor = yneth.rewardsDistributor();
        uint originalAllocatedETHForDeposits = yneth.totalDepositedInPool();
        bool originalIsDepositETHPaused = yneth.depositsPaused();
        uint originalTotalDepositedInPool = yneth.totalDepositedInPool();

        MockERC20 nETH = new MockERC20("Nest ETH", "nETH");
        nETH.mint(address(this), 100000 ether);

        address newImplementation = address(new MockYnETHERC4626()); 
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth)))
            .upgradeAndCall(ITransparentUpgradeableProxy(
                address(yneth)),
                newImplementation,
                abi.encodeWithSelector(MockYnETHERC4626.reinitialize.selector, MockYnETHERC4626.ReInit({underlyingAsset: nETH})
                )
            );

        MockYnETHERC4626 upgradedYnETH = MockYnETHERC4626(payable(address(yneth)));

        // Assert that all fields are equal post-upgrade
        assertEq(address(upgradedYnETH.stakingNodesManager()), address(originalStakingNodesManager), "StakingNodesManager mismatch");
        assertEq(address(upgradedYnETH.rewardsDistributor()), address(originalRewardsDistributor), "RewardsDistributor mismatch");
        assertEq(upgradedYnETH.totalDepositedInPool(), originalAllocatedETHForDeposits, "AllocatedETHForDeposits mismatch");
        assertEq(upgradedYnETH.depositsPaused(), originalIsDepositETHPaused, "IsDepositETHPaused mismatch");
        assertEq(upgradedYnETH.totalDepositedInPool(), originalTotalDepositedInPool, "TotalDepositedInPool mismatch");

        assertEq(finalTotalAssets, yneth.totalAssets(), "Total assets mismatch after upgrade");
        assertEq(finalTotalSupply, yneth.totalSupply(), "Total supply mismatch after upgrade");

        uint256 nETHDepositAmount = 100 ether;
        nETH.approve(address(yneth), nETHDepositAmount);
        vm.prank(address(this));
        upgradedYnETH.deposit(nETHDepositAmount, address(this));
    }

    function setupInitializeYnLSD(address assetAddress) internal returns (ynLSD.Init memory, ynLSD ynlsd) {
        TransparentUpgradeableProxy ynlsdProxy;
        ynlsd = ynLSD(payable(ynlsdProxy));

        // Re-deploying ynLSD and creating its proxy again
        ynlsd = new ynLSD();
        ynlsdProxy = new TransparentUpgradeableProxy(address(ynlsd), actors.PROXY_ADMIN_OWNER, "");
        ynlsd = ynLSD(payable(ynlsdProxy));

        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.DEFAULT_SIGNER;

        IERC20[] memory assets = new IERC20[](2);
        address[] memory assetsAddresses = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        IStrategy[] memory strategies = new IStrategy[](2);

        // rETH
        assets[0] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assetsAddresses[0] = chainAddresses.lsd.RETH_ADDRESS;
        strategies[0] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);
        priceFeeds[0] = chainAddresses.lsd.RETH_FEED_ADDRESS;
        maxAges[0] = uint256(86400);

        // Zero Addresses
        assets[1] = IERC20(assetAddress);
        assetsAddresses[1] = chainAddresses.lsd.STETH_ADDRESS;
        strategies[1] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);
        priceFeeds[1] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[1] = uint256(86400); //one hour

        ynLSD.Init memory init = ynLSD.Init({
            assets: assets,
            strategies: strategies,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            oracle: yieldNestOracle,
            maxNodeCount: 10,
            admin: actors.ADMIN,
            stakingAdmin: actors.STAKING_ADMIN,
            lsdRestakingManager: actors.LSD_RESTAKING_MANAGER,
            lsdStakingNodeCreatorRole: actors.STAKING_NODE_CREATOR,
            pauseWhitelist: pauseWhitelist,
            pauser: actors.PAUSE_ADMIN,
            depositBootstrapper: actors.DEPOSIT_BOOTSTRAPER
        });

        return (init, ynlsd);
    }

    function testYnLSDInitializeRevertsAssetAddressZero() public {
        (ynLSD.Init memory init, ynLSD ynlsd) = setupInitializeYnLSD(address(0));
        bytes memory encodedError = abi.encodeWithSelector(ynLSD.ZeroAddress.selector);
        vm.expectRevert(encodedError);
        ynlsd.initialize(init);
    }
}
