
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/ynViewer.sol";
import "../../../src/ynETH.sol";
import "../../../src/mocks/MockStakingNode.sol";
import "../../../src/mocks/ynETHERC4626.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradesTest is IntegrationBaseTest {

    function testUpgradeEachContract() public {

        address newImplementation = address(new ynETHERC4626()); 
        vm.prank(proxyAdmin);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");

        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        assertEq(currentImplementation, newImplementation);

        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        vm.prank(proxyAdmin);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerImpl);

        address newRewardsDistributorImpl = address(new RewardsDistributor());
        vm.prank(proxyAdmin);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        address currentRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        assertEq(currentRewardsDistributorImpl, newRewardsDistributorImpl);
    }
}
