// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import { Invariants } from "test/scenarios/Invariants.sol";

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "test/mocks/TestStakingNodeV2.sol";

import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";

contract ProtocolUpgradeScenario is ScenarioBaseTest {

    address YNSecurityCouncil;

    function setUp() public override {
        super.setUp();
        YNSecurityCouncil = actors.wallets.YNSecurityCouncil;
    }
    
    function test_Upgrade_ynETH_Scenario() public {
        address previousImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth));
        address newImplementation = address(new ynETH()); 

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();

        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newImplementation, "");

        runUpgradeInvariants(address(yneth), previousImplementation, newImplementation);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }
    
    function skip_test_Upgrade_StakingNodesManager_Scenario() public {
        address previousStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(stakingNodesManager));
        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        
        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();

        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");
        
        runUpgradeInvariants(address(stakingNodesManager), previousStakingNodesManagerImpl, newStakingNodesManagerImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_RewardsDistributor_Scenario() public {
        address previousRewardsDistributorImpl = getTransparentUpgradeableProxyImplementationAddress(address(rewardsDistributor));
        address newRewardsDistributorImpl = address(new RewardsDistributor());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(rewardsDistributor))).upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsDistributor)), newRewardsDistributorImpl, "");
        
        runUpgradeInvariants(address(rewardsDistributor), previousRewardsDistributorImpl, newRewardsDistributorImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_ExecutionLayerReceiver_Scenario() public {
        address previousExecutionLayerReceiverImpl = getTransparentUpgradeableProxyImplementationAddress(address(executionLayerReceiver));
        address newExecutionLayerReceiverImpl = address(new RewardsReceiver());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(executionLayerReceiver))).upgradeAndCall(ITransparentUpgradeableProxy(address(executionLayerReceiver)), newExecutionLayerReceiverImpl, "");
        
        runUpgradeInvariants(address(executionLayerReceiver), previousExecutionLayerReceiverImpl, newExecutionLayerReceiverImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_ConsensusLayerReceiver_Scenario() public {
        address previousConsensusLayerReceiverImpl = getTransparentUpgradeableProxyImplementationAddress(address(consensusLayerReceiver));
        address newConsensusLayerReceiverImpl = address(new RewardsReceiver());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(consensusLayerReceiver))).upgradeAndCall(ITransparentUpgradeableProxy(address(consensusLayerReceiver)), newConsensusLayerReceiverImpl, "");
        
        runUpgradeInvariants(address(consensusLayerReceiver), previousConsensusLayerReceiverImpl, newConsensusLayerReceiverImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_WithdrawalQueueManager_Scenario() public {
        address previousWithdrawalQueueManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynETHWithdrawalQueueManager));
        address newWithdrawalQueueManagerImpl = address(new WithdrawalQueueManager());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynETHWithdrawalQueueManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynETHWithdrawalQueueManager)), newWithdrawalQueueManagerImpl, "");
        
        runUpgradeInvariants(address(ynETHWithdrawalQueueManager), previousWithdrawalQueueManagerImpl, newWithdrawalQueueManagerImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_WithdrawalsProcessor_Scenario() public {
        address previousWithdrawalsProcessorImpl = getTransparentUpgradeableProxyImplementationAddress(address(withdrawalsProcessor));
        address newWithdrawalsProcessorImpl = address(new WithdrawalsProcessor());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(withdrawalsProcessor))).upgradeAndCall(ITransparentUpgradeableProxy(address(withdrawalsProcessor)), newWithdrawalsProcessorImpl, "");
        
        runUpgradeInvariants(address(withdrawalsProcessor), previousWithdrawalsProcessorImpl, newWithdrawalsProcessorImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_YnETHRedemptionAssetsVault_Scenario() public {
        address previousYnETHRedemptionAssetsVaultImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynETHRedemptionAssetsVaultInstance));
        address newYnETHRedemptionAssetsVaultImpl = address(new ynETHRedemptionAssetsVault());

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();
        
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynETHRedemptionAssetsVaultInstance))).upgradeAndCall(ITransparentUpgradeableProxy(address(ynETHRedemptionAssetsVaultInstance)), newYnETHRedemptionAssetsVaultImpl, "");
        
        runUpgradeInvariants(address(ynETHRedemptionAssetsVaultInstance), previousYnETHRedemptionAssetsVaultImpl, newYnETHRedemptionAssetsVaultImpl);
        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function skip_test_Upgrade_StakingNodeImplementation_Scenario() public {
        // Collect all existing eigenPod addresses before the upgrade
        IStakingNode[] memory stakingNodes = stakingNodesManager.getAllNodes();
        address[] memory eigenPodAddressesBefore = new address[](stakingNodes.length);
        for (uint i = 0; i < stakingNodes.length; i++) {
            eigenPodAddressesBefore[i] = address(stakingNodes[i].eigenPod());
        }

        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();

        // Upgrade the StakingNodeManager to support the new initialization version.
        address newStakingNodesManagerImpl = address(new TestStakingNodesManagerV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");

        TestStakingNodeV2 testStakingNodeV2 = new TestStakingNodeV2();
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(payable(testStakingNodeV2));

        UpgradeableBeacon beacon = stakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, payable(testStakingNodeV2));

        // Collect all existing eigenPod addresses after the upgrade
        address[] memory eigenPodAddressesAfter = new address[](stakingNodes.length);
        for (uint i = 0; i < stakingNodes.length; i++) {
            eigenPodAddressesAfter[i] = address(stakingNodes[i].eigenPod());
        }

        // Compare eigenPod addresses before and after the upgrade
        for (uint i = 0; i < stakingNodes.length; i++) {
            assertEq(eigenPodAddressesAfter[i], eigenPodAddressesBefore[i], "EigenPod address mismatch after upgrade");
        }

        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);
    }

    function runUpgradeInvariants(
        address proxyAddress,
        address previousImplementation,
        address newImplementation
    ) internal {
        // Check that the new implementation address is correctly set
        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(proxyAddress);
        assertEq(currentImplementation, newImplementation, "Invariant: Implementation address should match the new implementation address");
        // Ensure the implementation address has actually changed
        assertNotEq(previousImplementation, newImplementation, "Invariant: New implementation should be different from the previous one");
    }

    function runSystemStateInvariants(
        uint256 previousTotalDeposited,
        uint256 previousTotalAssets,
        uint256 previousTotalSupply
    ) public {  
        assertEq(yneth.totalDepositedInPool(), previousTotalDeposited, "Total deposit integrity check failed");
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
	}
}
