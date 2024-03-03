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
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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
}
