
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/ynViewer.sol";
import "../mocks/MockStakingNode.sol";
import "../mocks/MockYnETHERC4626.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../mocks/MockERC20.sol";


contract UpgradesTest is IntegrationBaseTest {

    function testUpgradeEachTransparentProxyUpgradeableContract() public {

<<<<<<< HEAD
        // address newImplementation = address(new ynETHERC4626()); 
        // vm.prank(proxyAdmin);
        // ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");
=======
        address newImplementation = address(new ynETH()); 
        vm.prank(proxyAdmin);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");
>>>>>>> feature/yieldnest-v1

        // address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        // assertEq(currentImplementation, newImplementation);

        // address newStakingNodesManagerImpl = address(new StakingNodesManager());
        // vm.prank(proxyAdmin);
        // ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        // address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        // assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerImpl);

        // address newRewardsDistributorImpl = address(new RewardsDistributor());
        // vm.prank(proxyAdmin);
        // ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        // address currentRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        // assertEq(currentRewardsDistributorImpl, newRewardsDistributorImpl);
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
        bool originalIsDepositETHPaused = yneth.isDepositETHPaused();
        uint originalExchangeAdjustmentRate = yneth.exchangeAdjustmentRate();
        uint originalTotalDepositedInPool = yneth.totalDepositedInPool();

        MockERC20 nETH = new MockERC20("Nest ETH", "nETH");
        nETH.mint(address(this), 100000 ether);

        address newImplementation = address(new MockYnETHERC4626()); 
        vm.prank(proxyAdmin);
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
        assertEq(upgradedYnETH.isDepositETHPaused(), originalIsDepositETHPaused, "IsDepositETHPaused mismatch");
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
