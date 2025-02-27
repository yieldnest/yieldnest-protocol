// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WithSlashingBase} from "test/integration/ynEIGEN/WithSlashingBase.t.sol";

contract TokenStakingNodeWithSlashingTest is WithSlashingBase {
    function testQueuedSharesAreNotUpdatedIfSynchronizeIsNotCalled_FullSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        assertEq(_queuedShares(), withdrawableShares, "Queued shares should be equal to withdrawable shares");

        _slash();

        assertEq(_queuedShares(), withdrawableShares, "Queued shares should be the same if it has not been synchronized after a slash");
    }

    function testQueuedSharesAreUpdatedAfterSynchronize_FullSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash();

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), 0, "After a complete slash, queued shares should be 0");
    }

    function testQueuedSharesAreDecreasedByHalf_HalfSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), withdrawableShares / 2, "After half is slashed queued shares should be half of the previous withdrawable shares");
    }

    function testQueuedSharesAreDecreasedByHalf_FullSlashed_HalfAllocated() public {
        _allocate(0.5 ether);

        _waitForDeallocationDelay();

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash();

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), withdrawableShares / 2, "After half is slashed queued shares should be half of the previous withdrawable shares");
    }

    function testQueuedSharesAreDecreasedToQuarter_HalfSlashed_HalfAllocated() public {
        _allocate(0.5 ether);

        _waitForDeallocationDelay();

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertApproxEqAbs(_queuedShares(), withdrawableShares - withdrawableShares / 4, 1, "After half is slashed and half is allocated, queued shares should be a quarter of the previous withdrawable shares");
    }

    function testCompleteFailsIfNotSynchronized() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash();

        _waitForWithdrawalDelay();

        vm.expectRevert(abi.encodeWithSelector(TokenStakingNode.NotSyncedAfterSlashing.selector, queuedWithdrawalRoot, 1 ether, 0));
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
    }

    function testCompleteFailsOnFullSlash() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash();

        _waitForWithdrawalDelay();

        tokenStakingNode.synchronize();

        vm.expectRevert("wstETH: can't wrap zero stETH");
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
    }

    function testQueuedSharesStorageVariablesAreUpdatedOnSynchronize() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 1 ether, "Max magnitude should be WAD");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares, "Queued withdrawable shares for withdrawalshould be equal to withdrawable shares");

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares / 2, "Queued shares should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0.5 ether, "Max magnitude should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares / 2, "Queued withdrawable shares for withdrawalshould be equal to half of the previous withdrawable shares");
    }

    function testSyncWithMultipleQueuedWithdrawals() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares / 2, 2, "Queued shares should be half of the previous withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 0.5 ether, "Max magnitude for withdrawal 1 should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 0.5 ether, "Max magnitude for withdrawal 2 should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 0.5 ether, "Max magnitude for withdrawal 3 should be half of the previous withdrawable shares");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 2 / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 2 / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 2 / 3");
    }

    function testSyncWithMultipleQueuedWithdrawals_NoSlashing() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");
    }

    function testQueuedSharesSyncedEventIsEmittedOnSynchronize() public {
        vm.expectEmit();
        emit QueuedSharesSynced();
        tokenStakingNode.synchronize();
    }

    function testQueuedSharesStorageVariablesResetOnComplete() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash(0.5 ether);

        _waitForWithdrawalDelay();

        tokenStakingNode.synchronize();

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0, "Max magnitude should be 0");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), 0, "Queued withdrawable shares should be 0");
    }

    function testQueueAndCompleteWhenUndelegated() public {
        // Create token staking node
        // TODO: Use TOKEN_STAKING_NODE_CREATOR_ROLE instead of STAKING_NODE_CREATOR
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        // Deposit assets to ynEigen
        uint256 stakeAmount = 100 ether;
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

        // Stake assets into the token staking node
        uint256 nodeId = tokenStakingNode.nodeId();
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = wstETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares, "Withdrawable shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 1 ether, "Max magnitude should be WAD");

        _waitForWithdrawalDelay();

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
        
        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), 0, "Withdrawable shares should be 0");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0, "Max magnitude should be 0");
    }

    function testInitializeV3AssignsQueuedSharesToLegacyQueuedShares() public {
        IERC20[] memory assets = assetRegistry.getAssets();

        assertGt(assets.length, 0, "There should be at least 1 asset");

        ITokenStakingNode node = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        node.initialize(init);

        node.initializeV2();

        uint256 legacyQueuedShares = 100 ether;

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            vm.store(
                address(node),
                keccak256(abi.encode(strategy, uint256(2))),
                bytes32(legacyQueuedShares * i)
            );

            assertEq(node.queuedShares(strategy), legacyQueuedShares * i, "Queued shares should be equal to the initial amount");
            assertEq(node.legacyQueuedShares(strategy), 0, "Legacy queued shares should be 0");
        }

        node.initializeV3();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            assertEq(node.queuedShares(strategy), 0, "Queued shares should be 0");
            assertEq(node.legacyQueuedShares(strategy), legacyQueuedShares * i, "Legacy queued shares should be equal to the initial amount");
        }
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndLegacyQueuedShares() public {
        ITokenStakingNode node = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        node.initialize(init);
        node.initializeV2();

        uint256 legacyQueuedShares = 100 ether;

        vm.store(
            address(node),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(legacyQueuedShares)
        );

        node.initializeV3();

        assertEq(node.legacyQueuedShares(wstETHStrategy), legacyQueuedShares, "Legacy queued shares should be equal to the initial amount");

        (uint256 queuedShares,) = node.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, node.legacyQueuedShares(wstETHStrategy), "Queued shares should be equal to the legacy queued shares");
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndLegacyQueuedShares_WithQueuedWithdrawals() public {
        tokenStakingNode = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        tokenStakingNode.initialize(init);
        tokenStakingNode.initializeV2();

        uint256 legacyQueuedShares = 100 ether;

        vm.store(
            address(tokenStakingNode),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(legacyQueuedShares)
        );

        tokenStakingNode.initializeV3();

        // Add the new node to the nodes array in the TokenStakingNodesManager.
        {
            uint256 currentNodesLength = tokenStakingNodesManager.nodesLength();
            
            // Increase the length of the nodes array.
            vm.store(
                address(tokenStakingNodesManager),
                bytes32(uint256(4)),
                bytes32(currentNodesLength + 1)
            );

            bytes32 nodesBaseSlot = keccak256(abi.encode(uint256(4)));

            // Update the last element of the nodes array to point to the new node.
            vm.store(
                address(tokenStakingNodesManager),
                bytes32(uint256(nodesBaseSlot) + currentNodesLength),
                bytes32(uint256(uint160(address(tokenStakingNode))))
            );
        }

        ITokenStakingNode retrievedNode = ITokenStakingNode(tokenStakingNodesManager.nodes(tokenStakingNodesManager.nodesLength() - 1));

        assertEq(address(retrievedNode), address(tokenStakingNode), "The retrieved node should be the same as the node we stored");

        // Deposit assets to ynEigen
        uint256 stakeAmount = 100 ether;
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

        // Stake assets into the token staking node
        uint256 nodeId = tokenStakingNode.nodeId();
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = wstETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to the deposit shares");
        assertEq(tokenStakingNode.legacyQueuedShares(wstETHStrategy), legacyQueuedShares, "Legacy queued shares should be equal to the deposit shares");

        (uint256 queuedShares,) = tokenStakingNode.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, withdrawableShares + legacyQueuedShares, "Queued shares should be equal to the sum of the queued shares and the legacy queued shares");
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndLegacyQueuedShares_WithQueuedWithdrawals_WithHalfSlashing() public {
        tokenStakingNode = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        tokenStakingNode.initialize(init);
        tokenStakingNode.initializeV2();

        uint256 legacyQueuedShares = 100 ether;

        vm.store(
            address(tokenStakingNode),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(legacyQueuedShares)
        );

        tokenStakingNode.initializeV3();

        // Add the new node to the nodes array in the TokenStakingNodesManager.
        {
            uint256 currentNodesLength = tokenStakingNodesManager.nodesLength();
            
            // Increase the length of the nodes array.
            vm.store(
                address(tokenStakingNodesManager),
                bytes32(uint256(4)),
                bytes32(currentNodesLength + 1)
            );

            bytes32 nodesBaseSlot = keccak256(abi.encode(uint256(4)));

            // Update the last element of the nodes array to point to the new node.
            vm.store(
                address(tokenStakingNodesManager),
                bytes32(uint256(nodesBaseSlot) + currentNodesLength),
                bytes32(uint256(uint160(address(tokenStakingNode))))
            );
        }

        ITokenStakingNode retrievedNode = ITokenStakingNode(tokenStakingNodesManager.nodes(tokenStakingNodesManager.nodesLength() - 1));

        assertEq(address(retrievedNode), address(tokenStakingNode), "The retrieved node should be the same as the node we stored");

        // Deposit assets to ynEigen
        uint256 stakeAmount = 100 ether;
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

        // Stake assets into the token staking node
        uint256 nodeId = tokenStakingNode.nodeId();
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = wstETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
        tokenStakingNode.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, approverSalt);

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        uint256 expectedQueuedShares = withdrawableShares / 2;

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), expectedQueuedShares, "Queued shares should be equal to half of the deposit shares");
        assertEq(tokenStakingNode.legacyQueuedShares(wstETHStrategy), legacyQueuedShares, "Legacy queued shares should be equal to the deposit shares");

        (uint256 queuedShares,) = tokenStakingNode.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, expectedQueuedShares + legacyQueuedShares, "Queued shares should be equal to half of the deposit shares plus the legacy queued shares");
    }
}
