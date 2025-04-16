// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynLSDeScenarioBaseTest} from "./ynLSDeScenarioBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/src/contracts/interfaces/IPermissionController.sol";
import {IPauserRegistry} from "@eigenlayer/src/contracts/interfaces/IPauserRegistry.sol";
import {IETHPOSDeposit} from "@eigenlayer/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IBeacon} from "@openzeppelin-v4.9.0/contracts/proxy/beacon/IBeacon.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {AllocationManager} from "@eigenlayer/src/contracts/core/AllocationManager.sol";
import {DelegationManager} from "@eigenlayer/src/contracts/core/DelegationManager.sol";
import {EigenPodManager} from "@eigenlayer/src/contracts/pods/EigenPodManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";
import {StrategyManager} from "@eigenlayer/src/contracts/core/StrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {WithdrawalsProcessor} from "src/ynEIGEN/WithdrawalsProcessor.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TestUpgradeUtils} from "test/utils/TestUpgradeUtils.sol";

contract ynEigenUpgradeScenarios is ynLSDeScenarioBaseTest {
    uint256 public constant WSTETH_AMOUNT = 10 ether;

    IAllocationManager public allocationManager;
    WithdrawalsProcessor public withdrawalsProcessor;

    address private user1;

    IPauserRegistry public pauserRegistry = IPauserRegistry(0x0c431C66F4dE941d089625E5B423D00707977060);
    IETHPOSDeposit public ethposDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    IBeacon public eigenPodBeacon = IBeacon(0x5a2a4F2F3C18f09179B6703e63D9eDD165909073);

    // Test state capture
    struct SystemSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 userBalance;
        uint256 wstEthBalance;
        uint256 tokenStakingNodesCount;
        uint256[] queuedShares;
    }

    modifier configure {
        // Not using chainIds.mainnet because it will be declared on assignContracts which has to be done after vm.rollFork.
        // Checking the chainId first to prevent rolling into a block number that does not exist on other chains.
        // todo: remove this skip once others are refactored
        // vm.skip(block.chainid == 1);
        // vm.rollFork(22046726); // Mar-14-2025 05:52:23 PM +UTC
        assignContracts(false);

        withdrawalsProcessor = WithdrawalsProcessor(chainAddresses.ynEigen.WITHDRAWALS_PROCESSOR_ADDRESS);
        user1 = makeAddr("user1");
        deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user1, give: WSTETH_AMOUNT});

        _;
    }

    function setUp() public virtual override {
        // NOTE: I don't want to run setup here because I need precise fork configuration.
        // These tests only need to be run on mainnet at a certain block number.
        // The expected setup is done on configure modifier.
    }

    function testDepositAndWithdrawAfterELUpgradeAndBeforeynEigenUpgrade() public configure {
        SystemSnapshot memory beforeState = getSystemSnapshot(user1);
        
        upgradeEigenLayerContracts();
        
        vm.startPrank(user1);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(yneigen), WSTETH_AMOUNT);
        uint256 sharesBefore = yneigen.balanceOf(user1);
        // The user can still deposit despite eigen breaking changes.
        yneigen.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), WSTETH_AMOUNT, user1);
        uint256 sharesAfter = yneigen.balanceOf(user1);
        vm.stopPrank();
        
        // Capture system state after deposit
        SystemSnapshot memory afterState = getSystemSnapshot(user1);
        
        uint256 sharesMinted = sharesAfter - sharesBefore;
        assertGt(sharesMinted, 0, "No shares were minted");
        assertGt(afterState.totalAssets, beforeState.totalAssets, "Total assets should increase after deposit");
        assertEq(afterState.totalSupply, beforeState.totalSupply + sharesMinted, "Total supply didn't increase by shares minted");
        assertEq(afterState.userBalance, beforeState.userBalance + sharesMinted, "User balance didn't increase by shares minted");
        assertEq(afterState.wstEthBalance, beforeState.wstEthBalance - WSTETH_AMOUNT, "wstETH wasn't transferred from user");
        assertEq(afterState.tokenStakingNodesCount, beforeState.tokenStakingNodesCount, "Number of staking nodes shouldn't change");

        // Stake assets to node
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        IERC20[] memory singleAsset = new IERC20[](1);
        singleAsset[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256[] memory singleAmount = new uint256[](1);
        singleAmount[0] = WSTETH_AMOUNT;
        vm.stopPrank();

        // Request Withdrawal
        vm.startPrank(user1);
        uint256 yneigenBalance = yneigen.balanceOf(user1);
        yneigen.approve(address(withdrawalQueueManager), yneigenBalance);
        // The user should still be able to request a withdrawal.
        uint256 tokenId = withdrawalQueueManager.requestWithdrawal(1 ether);
        vm.stopPrank();

        vm.prank(address(withdrawalsProcessor));
        uint256 finalizationId = withdrawalQueueManager.finalizeRequestsUpToIndex(tokenId + 1);


        IWithdrawalQueueManager.WithdrawalClaim[] memory claims = new IWithdrawalQueueManager.WithdrawalClaim[](1);
        claims[0] = IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: tokenId,
            finalizationId: finalizationId,
            receiver: user1
        });

        vm.startPrank(user1);
        withdrawalQueueManager.claimWithdrawals(claims);

        IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = withdrawalQueueManager.withdrawalRequest(tokenId);
        assertEq(_withdrawalRequest.processed, true, "withdrawal not processed");       
    }

    function testDepositAndWithdrawAfterELUpgradeAndAfterynEigenUpgrade() public configure {
        SystemSnapshot memory beforeState = getSystemSnapshot(user1);
        
        upgradeEigenLayerContracts();
        upgradeynEigenContracts();
        
        vm.startPrank(user1);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(yneigen), WSTETH_AMOUNT);
        uint256 sharesBefore = yneigen.balanceOf(user1);
        yneigen.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), WSTETH_AMOUNT, user1);
        uint256 sharesAfter = yneigen.balanceOf(user1);
        vm.stopPrank();
        
        // Capture system state after deposit
        SystemSnapshot memory afterState = getSystemSnapshot(user1);
        
        uint256 sharesMinted = sharesAfter - sharesBefore;
        assertGt(sharesMinted, 0, "No shares were minted");
        assertGt(afterState.totalAssets, beforeState.totalAssets, "Total assets should increase after deposit");
        assertEq(afterState.totalSupply, beforeState.totalSupply + sharesMinted, "Total supply didn't increase by shares minted");
        assertEq(afterState.userBalance, beforeState.userBalance + sharesMinted, "User balance didn't increase by shares minted");
        assertEq(afterState.wstEthBalance, beforeState.wstEthBalance - WSTETH_AMOUNT, "wstETH wasn't transferred from user");
        assertEq(afterState.tokenStakingNodesCount, beforeState.tokenStakingNodesCount, "Number of staking nodes shouldn't change");

        // Stake assets to node
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        IERC20[] memory singleAsset = new IERC20[](1);
        singleAsset[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256[] memory singleAmount = new uint256[](1);
        singleAmount[0] = WSTETH_AMOUNT;
        eigenStrategyManager.stakeAssetsToNode(0, singleAsset, singleAmount);
        vm.stopPrank();

        // Request Withdrawal
        vm.startPrank(user1);
        uint256 yneigenBalance = yneigen.balanceOf(user1);
        yneigen.approve(address(withdrawalQueueManager), yneigenBalance);
        withdrawalQueueManager.requestWithdrawal(yneigenBalance);
        vm.stopPrank();

        // Queue Withdrawals
        WithdrawalsProcessor.QueueWithdrawalsArgs memory queueArgs = withdrawalsProcessor.getQueueWithdrawalsArgs();
        
        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        withdrawalsProcessor.queueWithdrawals(queueArgs);

        // Capture system state after withdrawal
        afterState = getSystemSnapshot(user1);

        for (uint256 i = 0; i < tokenStakingNodesManager.nodesLength(); i++) {
            ITokenStakingNode node = tokenStakingNodesManager.getNodeById(i);

            IStrategy strategy = eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));

            assertEq(0, node.preELIP002QueuedSharesAmount(strategy));
            assertEq(true, node.isSynchronized());
        }
        
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        // Successfully call strategy manager functions
        eigenStrategyManager.getStakedAssetsBalances(assets);
    }
    
    function testSynchronizeNodesAndUpdateBalancesAfterELUpgradeAndAfterYnEigenUpgrade() public configure {
        // Update token staking nodes balances before upgrade
        // sync before
        IERC20[] memory assets = assetRegistry.getAssets();
        {
            uint256 assetsLength = assets.length;
            for (uint256 i = 0; i < assetsLength; i++) {
                eigenStrategyManager.updateTokenStakingNodesBalances(assets[i]);
            }
        }


        SystemSnapshot memory beforeState = getSystemSnapshot(user1);

        // Verify staked assets balances before synchronization
        uint256[] memory balancesBefore = eigenStrategyManager.getStakedAssetsBalances(assets);

        upgradeEigenLayerContracts();
        upgradeynEigenContracts();

        eigenStrategyManager.synchronizeNodesAndUpdateBalances(tokenStakingNodesManager.getAllNodes());

        // Verify staked assets balances after synchronization
        uint256[] memory balancesAfter = eigenStrategyManager.getStakedAssetsBalances(assets);
        
        // Compare balances before and after synchronization
        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(
                balancesBefore[i], 
                balancesAfter[i], 
                "Staked asset balances should remain the same after synchronization"
            );
        }

        // Capture system state after upgrade and synchronization
        SystemSnapshot memory afterState = getSystemSnapshot(user1);
        
        // Compare before and after states to ensure system integrity
        assertEq(beforeState.totalAssets, afterState.totalAssets, "Total assets should remain the same after upgrade");
        assertEq(beforeState.totalSupply, afterState.totalSupply, "Total supply should remain the same after upgrade");
        assertEq(beforeState.userBalance, afterState.userBalance, "User balance should remain the same after upgrade");
        
        // Verify nodes are properly synchronized
        for (uint256 i = 0; i < tokenStakingNodesManager.nodesLength(); i++) {
            ITokenStakingNode node = tokenStakingNodesManager.getNodeById(i);
            assertTrue(node.isSynchronized(), "Node should be synchronized after upgrade");
        }
    }

    
    function upgradeEigenLayerContracts() internal {

        TestUpgradeUtils.executeEigenlayerSlashingUpgrade();
    }

    function upgradeynEigenContracts() internal {

        {
            TokenStakingNodesManager newTokenStakingNodesManager = new TokenStakingNodesManager();
            address tokenStakingNodesManagerImpl = address(newTokenStakingNodesManager);
            vm.prank(address(timelockController));
            ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(tokenStakingNodesManager)), 
                tokenStakingNodesManagerImpl, 
                ""
            );
        }

        {
            TokenStakingNode newTokenStakingNode = new TokenStakingNode();
            vm.prank(address(timelockController));
            tokenStakingNodesManager.upgradeTokenStakingNode(address(newTokenStakingNode));
        }

        {
            // Deploy new EigenStrategyManager implementation
            address newEigenStrategyManagerImpl = address(new EigenStrategyManager());
            
            // Upgrade the proxy to the new implementation
            vm.prank(address(timelockController));
            ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(eigenStrategyManager))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(eigenStrategyManager)),
                newEigenStrategyManagerImpl,
                ""
            );
        }

        {
            // Deploy new AssetRegistry implementation
            address newAssetRegistryImpl = address(new AssetRegistry());
            
            // Upgrade the proxy to the new implementation
            vm.prank(address(timelockController));
            ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(assetRegistry))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(assetRegistry)),
                newAssetRegistryImpl,
                ""
            );
        }

        {
            WithdrawalsProcessor newWithdrawalsProcessor = new WithdrawalsProcessor(
                address(withdrawalsProcessor.withdrawalQueueManager()),
                address(withdrawalsProcessor.tokenStakingNodesManager()),
                address(withdrawalsProcessor.assetRegistry()),
                address(withdrawalsProcessor.ynStrategyManager()),
                address(withdrawalsProcessor.delegationManager()),
                address(withdrawalsProcessor.yneigen()),
                address(withdrawalsProcessor.redemptionAssetsVault()),
                address(withdrawalsProcessor.wrapper()),
                address(withdrawalsProcessor.STETH()),
                address(withdrawalsProcessor.WSTETH()),
                address(withdrawalsProcessor.OETH()),
                address(withdrawalsProcessor.WOETH())
            );
            vm.prank(actors.admin.PROXY_ADMIN_OWNER);
            ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(withdrawalsProcessor))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(withdrawalsProcessor)),
                address(newWithdrawalsProcessor),
                ""
            );
            withdrawalsProcessor.initializeV2(address(this), 1.1 ether);
        }
    }
    
    function getSystemSnapshot(address user) internal view returns (SystemSnapshot memory) {
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256[] memory queuedShares = new uint256[](nodes.length);
        IStrategy strategy = eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));

        for (uint256 i = 0; i < nodes.length; i++) {
            queuedShares[i] = nodes[i].queuedShares(strategy);
        }
        
        return SystemSnapshot({
            totalAssets: yneigen.totalAssets(),
            totalSupply: yneigen.totalSupply(),
            userBalance: yneigen.balanceOf(user),
            wstEthBalance: IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user),
            tokenStakingNodesCount: tokenStakingNodesManager.nodesLength(),
            queuedShares: queuedShares
        });
    }
}
