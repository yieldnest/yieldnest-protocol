// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
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


    function testFuzz_QueuedSharesAreDecreased(uint64 allocationPercent, uint64 slashingPercent) public {

        vm.assume(allocationPercent > 0 && allocationPercent <= 1 ether);
        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        _allocate(allocationPercent);

        _waitForDeallocationDelay();

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash(slashingPercent);

        tokenStakingNode.synchronize();

        assertApproxEqRel(
            _queuedShares(),
            withdrawableShares - withdrawableShares * allocationPercent * slashingPercent / 1e18 / 1e18, 1e4,
        "After part is slashed and part is allocated, queued shares should be a fraction of the previous withdrawable shares: 1 - (allocationPercent * slashingPercent / 1e18 / 1e18)");
    }

    function testCompleteFailsIfNotSynchronized() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash();

        _waitForWithdrawalDelay();

        vm.expectRevert(abi.encodeWithSelector(TokenStakingNode.NotSyncedAfterSlashing.selector, queuedWithdrawalRoot));
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

    function testQueuedSharesStorageVariablesAreUpdatedOnSynchronize(uint256 slashingPercent) public {

        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to withdrawable shares");
        (uint256 withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot);
        assertEq(withdrawableShares1, withdrawableShares, "Queued withdrawable shares for withdrawal root should be equal to withdrawable shares");

        _slash(slashingPercent);

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares - withdrawableShares * slashingPercent / 1e18, 1, "Queued shares should be half of the previous withdrawable shares");
        (withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot);
        assertApproxEqAbs(withdrawableShares1, withdrawableShares - withdrawableShares * slashingPercent / 1e18, 1, "Queued withdrawable shares for withdrawal root should be equal to half of the previous withdrawable shares");
    }

    function testSyncWithMultipleQueuedWithdrawals(uint256 slashingPercent) public {
        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");
        (uint256 withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot1);
        assertEq(withdrawableShares1, withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        (uint256 withdrawableShares2, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot2);
        assertEq(withdrawableShares2, withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        (uint256 withdrawableShares3, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot3);
        assertEq(withdrawableShares3, withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        _slash(slashingPercent);

        tokenStakingNode.synchronize();

        uint256 totalWithdrawableSharesAfterSlashing = (withdrawableShares - withdrawableShares * slashingPercent / 1e18);
        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), totalWithdrawableSharesAfterSlashing, 5, "Queued shares should be reduced according to slashing percentage");
        (withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot1);


        assertApproxEqAbs(withdrawableShares1, totalWithdrawableSharesAfterSlashing / 3, 1, "Queued withdrawable for withdrawal 1 should be equal to slashed withdrawable shares / 3");
        (withdrawableShares2, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot2);
        assertApproxEqAbs(withdrawableShares2, totalWithdrawableSharesAfterSlashing / 3, 1, "Queued withdrawable for withdrawal 2 should be equal to slashed withdrawable shares / 3");
        (withdrawableShares3, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot3);
        assertApproxEqAbs(withdrawableShares3, totalWithdrawableSharesAfterSlashing / 3, 1, "Queued withdrawable for withdrawal 3 should be equal to slashed withdrawable shares / 3");
    }

    function testSyncWithMultipleQueuedWithdrawals_NoSlashing() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        (uint256 withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot1);
        assertEq(withdrawableShares1, withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        (uint256 withdrawableShares2, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot2);
        assertEq(withdrawableShares2, withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        (uint256 withdrawableShares3, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot3);
        assertEq(withdrawableShares3, withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        (withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot1);
        assertEq(withdrawableShares1, withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        (withdrawableShares2, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot2);
        assertEq(withdrawableShares2, withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        (withdrawableShares3, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot3);
        assertEq(withdrawableShares3, withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");
    }

    function testQueuedSharesSyncedEventIsEmittedOnSynchronize() public {
        vm.expectEmit();
        emit QueuedSharesSynced();
        tokenStakingNode.synchronize();
    }

    function testQueuedSharesStorageVariablesResetOnComplete(uint256 slashingPercent) public {

        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash(slashingPercent);

        _waitForWithdrawalDelay();

        tokenStakingNode.synchronize();

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        (uint256 withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot);
        assertEq(withdrawableShares1, 0, "Queued withdrawable shares should be 0");
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
        (uint256 withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot);
        assertEq(withdrawableShares1, withdrawableShares, "Withdrawable shares should be equal to withdrawable shares");

        _waitForWithdrawalDelay();

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
        
        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        (withdrawableShares1, ) = tokenStakingNode.withdrawableShareInfo(queuedWithdrawalRoot);
        assertEq(withdrawableShares1, 0, "Withdrawable shares should be 0");
    }

    function testInitializeV3AssignsQueuedSharesToPreELIP002QueuedSharesAmount() public {
        IERC20[] memory assets = assetRegistry.getAssets();

        assertGt(assets.length, 0, "There should be at least 1 asset");

        ITokenStakingNode node = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        node.initialize(init);

        node.initializeV2();

        uint256 preELIP002QueuedSharesAmount = 100 ether;

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            vm.store(
                address(node),
                keccak256(abi.encode(strategy, uint256(2))),
                bytes32(preELIP002QueuedSharesAmount * i)
            );

            assertEq(node.queuedShares(strategy), preELIP002QueuedSharesAmount * i, "Queued shares should be equal to the initial amount");
            assertEq(node.preELIP002QueuedSharesAmount(strategy), 0, "Pre ELIP-002 queued shares should be 0");
        }

        node.initializeV3();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            assertEq(node.queuedShares(strategy), 0, "Queued shares should be 0");
            assertEq(node.preELIP002QueuedSharesAmount(strategy), preELIP002QueuedSharesAmount * i, "Pre ELIP-002 queued shares should be equal to the initial amount");
        }
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndPreELIP002QueuedSharesAmount() public {
        ITokenStakingNode node = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        node.initialize(init);
        node.initializeV2();

        uint256 preELIP002QueuedSharesAmount = 100 ether;

        vm.store(
            address(node),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(preELIP002QueuedSharesAmount)
        );

        node.initializeV3();

        assertEq(node.preELIP002QueuedSharesAmount(wstETHStrategy), preELIP002QueuedSharesAmount, "Pre ELIP-002 queued shares should be equal to the initial amount");

        (uint256 queuedShares,) = node.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, node.preELIP002QueuedSharesAmount(wstETHStrategy), "Queued shares should be equal to the pre ELIP-002 queued shares");
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndPreELIP002QueuedSharesAmount_WithQueuedWithdrawals() public {
        tokenStakingNode = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        tokenStakingNode.initialize(init);
        tokenStakingNode.initializeV2();

        uint256 preELIP002QueuedSharesAmount = 100 ether;

        vm.store(
            address(tokenStakingNode),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(preELIP002QueuedSharesAmount)
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
        assertEq(tokenStakingNode.preELIP002QueuedSharesAmount(wstETHStrategy), preELIP002QueuedSharesAmount, "Pre ELIP-002 queued shares should be equal to the deposit shares");

        (uint256 queuedShares,) = tokenStakingNode.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, withdrawableShares + preELIP002QueuedSharesAmount, "Queued shares should be equal to the sum of the queued shares and the pre ELIP-002 queued shares");
    }

    function testGetQueuedSharesAndWithdrawnReturnsSumOfQueuedSharesAndPreELIP002QueuedSharesAmount_WithQueuedWithdrawals_WithSlashing(
         uint64 slashingPercent
    ) public {
        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        tokenStakingNode = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: tokenStakingNodesManager.nodesLength()
        });

        tokenStakingNode.initialize(init);
        tokenStakingNode.initializeV2();

        uint256 preELIP002QueuedSharesAmount = 100 ether;

        vm.store(
            address(tokenStakingNode),
            keccak256(abi.encode(wstETHStrategy, uint256(2))),
            bytes32(preELIP002QueuedSharesAmount)
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
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
        tokenStakingNode.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, approverSalt);

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        _slash(slashingPercent);

        tokenStakingNode.synchronize();

        uint256 expectedQueuedShares = withdrawableShares * (1 ether - slashingPercent) / 1 ether;

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), expectedQueuedShares, "Queued shares should be equal to (1 - slashingPercent) * deposit shares");
        assertEq(tokenStakingNode.preELIP002QueuedSharesAmount(wstETHStrategy), preELIP002QueuedSharesAmount, "Pre ELIP-002 queued shares should be equal to the deposit shares");

        (uint256 queuedShares,) = tokenStakingNode.getQueuedSharesAndWithdrawn(wstETHStrategy, wstETH);

        assertEq(queuedShares, expectedQueuedShares + preELIP002QueuedSharesAmount, "Queued shares should be equal to half of the deposit shares plus the pre ELIP-002 queued shares");
    }
}
