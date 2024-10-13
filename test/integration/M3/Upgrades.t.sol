// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {Base} from "./Base.t.sol";
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
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";

contract UpgradesWithdrawalsTest is Base {

    function testUpgradeWithdrawalQueueManager() public {
        address newImplementation = address(new WithdrawalQueueManager()); 
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynETHWithdrawalQueueManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynETHWithdrawalQueueManager)), newImplementation, "");

        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(ynETHWithdrawalQueueManager));
        assertEq(currentImplementation, newImplementation);
    }

    function testUpgradeWithdrawalsProcessor() public {
        address newImplementation = address(new WithdrawalsProcessor());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(withdrawalsProcessor))).upgradeAndCall(ITransparentUpgradeableProxy(address(withdrawalsProcessor)), newImplementation, "");
        
        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(withdrawalsProcessor));
        assertEq(currentImplementation, newImplementation);
    }

    function testUpgradeYnETHRedemptionAssetsVault() public {
        address newImplementation = address(new ynETHRedemptionAssetsVault());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynETHRedemptionAssetsVaultInstance))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynETHRedemptionAssetsVaultInstance)), newImplementation, "");
        
        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(ynETHRedemptionAssetsVaultInstance));
        assertEq(currentImplementation, newImplementation);
    }
}