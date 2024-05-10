// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import "forge-std/console.sol";


contract Upgrade_Scenario is ScenarioBaseTest {

    address YNSecurityCouncil = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    function testUpgradeYnETH() public {
        address newImplementation = address(new ynETH()); 
        vm.prank(YNSecurityCouncil);
        console.log("Proxy Admin Owner:", actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");

        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        assertEq(currentImplementation, newImplementation);
    }

    function testUpgradeStakingNodesManager() public {
        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        
        address currentStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        assertEq(currentStakingNodesManagerImpl, newStakingNodesManagerImpl);
    }

    function testUpgradeRewardsDistributor() public {
        address newRewardsDistributorImpl = address(new RewardsDistributor());
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        
        address currentRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        assertEq(currentRewardsDistributorImpl, newRewardsDistributorImpl);
    }

    function testUpgradeExecutionLayerReceiver() public {
        address newExecutionLayerReceiverImpl = address(new RewardsReceiver());
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(executionLayerReceiver))).upgradeAndCall(ITransparentUpgradeableProxy(address(executionLayerReceiver)), newExecutionLayerReceiverImpl, "");
        
        address currentExecutionLayerReceiverImpl = getTransparentUpgradeableProxyImplementationAddress(address(executionLayerReceiver));
        assertEq(currentExecutionLayerReceiverImpl, newExecutionLayerReceiverImpl);
    }

    function testUpgradeConsensusLayerReceiver() public {
        address newConsensusLayerReceiverImpl = address(new RewardsReceiver());
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(consensusLayerReceiver))).upgradeAndCall(ITransparentUpgradeableProxy(address(consensusLayerReceiver)), newConsensusLayerReceiverImpl, "");
        
        address currentConsensusLayerReceiverImpl = getTransparentUpgradeableProxyImplementationAddress(address(consensusLayerReceiver));
        assertEq(currentConsensusLayerReceiverImpl, newConsensusLayerReceiverImpl);
    }

}
