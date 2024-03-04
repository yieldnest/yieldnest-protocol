// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {StakingNodesManager} from "../../../src/StakingNodesManager.sol";
import {ynETH} from "../../../src/ynETH.sol";
import {ynLSD} from "../../../src/ynLSD.sol";
import {YieldNestOracle} from "../../../src/YieldNestOracle.sol";
import {MockYnETHERC4626} from "../mocks/MockYnETHERC4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RewardsDistributor} from "../../../src/RewardsDistributor.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "../../../src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TestStakingNodesManagerV2} from "../mocks/TestStakingNodesManagerV2.sol";

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
        uint originalAllocatedETHForDeposits = yneth.allocatedETHForDeposits();
        bool originalIsDepositETHPaused = yneth.depositsPaused();
        uint originalExchangeAdjustmentRate = yneth.exchangeAdjustmentRate();
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
        assertEq(upgradedYnETH.allocatedETHForDeposits(), originalAllocatedETHForDeposits, "AllocatedETHForDeposits mismatch");
        assertEq(upgradedYnETH.depositsPaused(), originalIsDepositETHPaused, "IsDepositETHPaused mismatch");
        assertEq(upgradedYnETH.exchangeAdjustmentRate(), originalExchangeAdjustmentRate, "ExchangeAdjustmentRate mismatch");
        assertEq(upgradedYnETH.totalDepositedInPool(), originalTotalDepositedInPool, "TotalDepositedInPool mismatch");

        assertEq(finalTotalAssets, yneth.totalAssets(), "Total assets mismatch after upgrade");
        assertEq(finalTotalSupply, yneth.totalSupply(), "Total supply mismatch after upgrade");

        uint256 nETHDepositAmount = 100 ether;
        nETH.approve(address(yneth), nETHDepositAmount);
        vm.prank(address(this));
        upgradedYnETH.deposit(nETHDepositAmount, address(this));
    }

    function testUpgradeYnETHRevertswithInvalidAdjustmentRate() public {

        TransparentUpgradeableProxy ynethProxy;
        yneth = ynETH(payable(ynethProxy));

        // Re-deploying ynETH and creating its proxy again
        yneth = new ynETH();
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.PROXY_ADMIN_OWNER, "");
        yneth = ynETH(payable(ynethProxy));


        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.TRANSFER_ENABLED_EOA;
        
        uint256 invalidRate = 100000000000000000000;

        ynETH.Init memory ynethInit = ynETH.Init({
            admin: actors.ADMIN,
            pauser: actors.PAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            exchangeAdjustmentRate: invalidRate,
            pauseWhitelist: pauseWhitelist
        });

        bytes memory encodedError = abi.encodeWithSignature("ExchangeAdjustmentRateOutOfBounds(uint256)", invalidRate);

        vm.expectRevert(encodedError);
        yneth.initialize(ynethInit);
    }

    function testDepositEthWithZeroEth() public {
        bytes memory encodedError = abi.encodeWithSignature("ZeroETH()");
        vm.expectRevert(encodedError);
        yneth.depositETH{value: 0}(address(this));
    }

    function testReceiveRewardsWithBadRewardsDistributor() public {
        bytes memory encodedError = abi.encodeWithSignature("NotRewardsDistributor()");
        vm.expectRevert(encodedError);
        yneth.receiveRewards();
    }

    function testWithdrawETHWithZeroBalance() public {
        bytes memory encodedError = abi.encodeWithSignature("InsufficientBalance()");
        vm.startPrank(address(stakingNodesManager));
        vm.expectRevert(encodedError);
        yneth.withdrawETH(1);
        vm.stopPrank();
    }

    function testSetExchangeAdjustmentRate() public {
        uint256 newRate = 1000;
        vm.prank(address(stakingNodesManager));
        yneth.setExchangeAdjustmentRate(newRate);
        assertEq(yneth.exchangeAdjustmentRate(), newRate);
    }

    function testSetExchangeAdjustmentRateWithInvalidRate() public {
        uint256 invalidRate = 100000000000000000000;
        bytes memory encodedError = abi.encodeWithSignature("ValueOutOfBounds(uint256)", invalidRate);
        vm.startPrank(address(stakingNodesManager));
        vm.expectRevert(encodedError);
        yneth.setExchangeAdjustmentRate(invalidRate);
        vm.stopPrank();
    }
}
