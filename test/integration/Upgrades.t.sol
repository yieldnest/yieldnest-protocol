// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {MockYnETHERC4626} from "test/mocks/MockYnETHERC4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";

contract UpgradesTest is IntegrationBaseTest {

    function testUpgradeYnETH() public {
        address newImplementation = address(new ynETH()); 
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");

        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        assertEq(currentImplementation, newImplementation);
    }

    function testUpgradeStakingNodesManager() public {
        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        
        address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerImpl);
    }

    function testUpgradeRewardsDistributor() public {
        address newRewardsDistributorImpl = address(new RewardsDistributor());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        
        address currentRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        assertEq(currentRewardsDistributorImpl, newRewardsDistributorImpl);
    }

    // function testUpgradeYnLSD() public {
    //     address newYnLSDImpl = address(new ynLSD());
    //     vm.prank(actors.admin.PROXY_ADMIN_OWNER);
    //     ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newYnLSDImpl, "");
        
    //     address currentYnLSDImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynlsd));
    //     assertEq(currentYnLSDImpl, newYnLSDImpl);
    // }

    function testUpgradeStakingNodesManagerToV2AndReinit() public {
        TestStakingNodesManagerV2.ReInit memory reInit = TestStakingNodesManagerV2.ReInit({
            newV2Value: 42
        });

        address newStakingNodesManagerV2Impl = address(new TestStakingNodesManagerV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
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
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
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
}
