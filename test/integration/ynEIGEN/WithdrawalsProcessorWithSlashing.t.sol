// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {MockAVSRegistrar} from "lib/eigenlayer-contracts/src/test/mocks/MockAVSRegistrar.sol";
import {IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";
import {IWithdrawalsProcessor} from "../../../src/interfaces/IWithdrawalsProcessor.sol";
import {WithdrawalsProcessor} from "../../../src/ynEIGEN/WithdrawalsProcessor.sol";

import "./ynEigenIntegrationBaseTest.sol";

contract WithdrawalsProcessorWithSlashingTest is ynEigenIntegrationBaseTest {
    WithdrawalsProcessor private withdrawalsProcessor;

    address private user1;
    address private user2;
    address private operator1;
    address private operator2;
    address private keeper;
    address private bufferSetter;
    address private avs;

    ITokenStakingNode private node1;
    ITokenStakingNode private node2;

    IERC20 private wsteth;
    IERC20 private sfrxeth;

    function setUp() public virtual override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        keeper = makeAddr("keeper");
        bufferSetter = makeAddr("bufferSetter");
        address owner = makeAddr("owner");

        wsteth = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        sfrxeth = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

        // Setup the WithdrawalsProcessor.
        withdrawalsProcessor = new WithdrawalsProcessor(
            address(withdrawalQueueManager),
            address(tokenStakingNodesManager),
            address(assetRegistry),
            address(eigenStrategyManager),
            address(eigenLayer.delegationManager),
            address(ynEigenToken),
            address(redemptionAssetsVault),
            address(wrapper),
            chainAddresses.lsd.STETH_ADDRESS,
            chainAddresses.lsd.WSTETH_ADDRESS,
            chainAddresses.lsd.OETH_ADDRESS,
            chainAddresses.lsd.WOETH_ADDRESS
        );
        withdrawalsProcessor = WithdrawalsProcessor(address(new TransparentUpgradeableProxy(address(withdrawalsProcessor), actors.admin.PROXY_ADMIN_OWNER, "")));
        WithdrawalsProcessor(address(withdrawalsProcessor)).initialize(owner, keeper);
        WithdrawalsProcessor(address(withdrawalsProcessor)).initializeV2(bufferSetter, 1 ether);

        // Give the required permissions to the WithdrawalsProcessor.
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        eigenStrategyManager.grantRole(eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor));
        eigenStrategyManager.grantRole(eigenStrategyManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor));
        withdrawalQueueManager.grantRole(withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(withdrawalsProcessor));
        vm.stopPrank();

        // Give the required permissions to the WithdrawalQueueManager.
        vm.startPrank(actors.admin.STAKING_ADMIN);
        ynEigenToken.grantRole(ynEigenToken.BURNER_ROLE(), address(withdrawalQueueManager));
        vm.stopPrank();

        // Unpause transfers.
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.unpauseTransfers();

        // Create the token staking nodes.
        vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
        node1 = tokenStakingNodesManager.createTokenStakingNode();
        node2 = tokenStakingNodesManager.createTokenStakingNode();
        vm.stopPrank();

        // Register the operators.
        vm.prank(operator1);
        eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");
        vm.prank(operator2);
        eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");

        // Delegate the token staking nodes to the operators.
        ISignatureUtils.SignatureWithExpiry memory signature;
        vm.startPrank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
        node1.delegate(operator1, signature, bytes32(0));
        node2.delegate(operator2, signature, bytes32(0));
        vm.stopPrank();

        // Create the AVS.
        avs = address(new MockAVSRegistrar());

        // Update the AVS metadata URI.
        vm.prank(avs);
        eigenLayer.allocationManager.updateAVSMetadataURI(avs, "ipfs://some-metadata-uri");

        // Create the operator sets.
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({ 
            operatorSetId: 1, 
            strategies: new IStrategy[](2) 
        });
        createSetParams[0].strategies[0] = eigenStrategyManager.strategies(wsteth);
        createSetParams[0].strategies[1] = eigenStrategyManager.strategies(sfrxeth);
        vm.prank(avs);
        eigenLayer.allocationManager.createOperatorSets(avs, createSetParams);
        createSetParams[0].operatorSetId = 2;
        vm.prank(avs);
        eigenLayer.allocationManager.createOperatorSets(avs, createSetParams);

        // Register the operators for the operator sets.
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: avs,
            operatorSetIds: new uint32[](1),
            data: new bytes(0)
        });
        registerParams.operatorSetIds[0] = 1;
        vm.prank(operator1);
        eigenLayer.allocationManager.registerForOperatorSets(operator1, registerParams);
        registerParams.operatorSetIds[0] = 2;
        vm.prank(operator2);
        eigenLayer.allocationManager.registerForOperatorSets(operator2, registerParams);

        // Wait for the allocation configuration delay.
        vm.roll(block.number + AllocationManagerStorage(address(eigenLayer.allocationManager)).ALLOCATION_CONFIGURATION_DELAY() + 1);

        // Allocate operator stakes.
        IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocateParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet({
                avs: avs,
                id: 1
            }),
            strategies: new IStrategy[](2),
            newMagnitudes: new uint64[](2)
        });
        allocateParams[0].strategies[0] = eigenStrategyManager.strategies(wsteth);
        allocateParams[0].newMagnitudes[0] = 1 ether;
        allocateParams[0].strategies[1] = eigenStrategyManager.strategies(sfrxeth);
        allocateParams[0].newMagnitudes[1] = 1 ether;
        vm.prank(operator1);
        eigenLayer.allocationManager.modifyAllocations(operator1, allocateParams);
        allocateParams[0].operatorSet.id = 2;
        vm.prank(operator2);
        eigenLayer.allocationManager.modifyAllocations(operator2, allocateParams);

        // Provide users with wsteth.
        deal({token: address(wsteth), to: user1, give: 1000 ether});
        deal({token: address(wsteth), to: user2, give: 1000 ether});

        // Provide users with sfrxeth.
        deal({token: address(sfrxeth), to: user1, give: 1000 ether});
        deal({token: address(sfrxeth), to: user2, give: 1000 ether});
    }

    function _slash(address _operator, uint256 _wadsToSlash) public {
        // Slash the operator.
        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: _operator,
            operatorSetId: _operator == operator1 ? 1 : 2,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "test"
        });
        slashingParams.strategies[0] = eigenStrategyManager.strategies(_operator == operator1 ? wsteth : sfrxeth);
        slashingParams.wadsToSlash[0] = _wadsToSlash;
        vm.prank(avs);
        eigenLayer.allocationManager.slashOperator(avs, slashingParams);

        // Synchronize nodes and balances.
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
        nodes[0] = node1;
        nodes[1] = node2;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
    }

    function test_ReceivesSameValueOnClaimWithdraw() public {
        uint256 user1WstethDeposit = 100 ether;
        uint256 user2SfrxethDeposit = 200 ether;

        // User 1 deposits wsteth.
        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(wsteth, user1WstethDeposit, user1);
        vm.stopPrank();

        // User 2 deposits sfrxeth.
        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(sfrxeth, user2SfrxethDeposit, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1);
        uint256[] memory singleAmount = new uint256[](1);
        
        // Stake wsteth to node 1.
        singleAsset[0] = wsteth;
        singleAmount[0] = user1WstethDeposit;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        // Stake sfrxeth to node 2.
        singleAsset[0] = sfrxeth;
        singleAmount[0] = user2SfrxethDeposit;        
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1YnEigenTokenBalance = ynEigenToken.balanceOf(user1);

        // User 1 request to withdraw all their ynEigenToken balance.
        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), type(uint256).max);
        uint256 requestTokenId = withdrawalQueueManager.requestWithdrawal(user1YnEigenTokenBalance);
        vm.stopPrank();

        // Get the arguments and queue withdrawals.
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // Wait for the withdrawal delay and complete the withdrawal.
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // Process principal withdrawals.
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        uint256 user1SfrxethBalanceBefore = sfrxeth.balanceOf(user1);

        // User1 claims the withdrawn assets.
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestTokenId, user1);

        // Check that the user received the correct amount of sfrxeth.
        assertApproxEqAbs(
            assetRegistry.convertToUnitOfAccount(wsteth, user1WstethDeposit), 
            assetRegistry.convertToUnitOfAccount(sfrxeth, sfrxeth.balanceOf(user1) - user1SfrxethBalanceBefore),
            1e4,
            "The claimed sfrxeth should have the same value as the original wsteth deposit"
        );
    }

    function test_ReceivesSameValueOnClaimWithdraw_WithSlashing_PreRequest() public {
        uint256 user1WstethDeposit = 100 ether;
        uint256 user2SfrxethDeposit = 200 ether;

        // User 1 deposits wsteth.
        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(wsteth, user1WstethDeposit, user1);
        vm.stopPrank();

        // User 2 deposits sfrxeth.
        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(sfrxeth, user2SfrxethDeposit, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1);
        uint256[] memory singleAmount = new uint256[](1);
        
        // Stake wsteth to node 1.
        singleAsset[0] = wsteth;
        singleAmount[0] = user1WstethDeposit;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        // Stake sfrxeth to node 2.
        singleAsset[0] = sfrxeth;
        singleAmount[0] = user2SfrxethDeposit;        
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1YnEigenTokenBalance = ynEigenToken.balanceOf(user1);

        // Slash 🗡️
        // Before requesting withdrawals.
        // This will cause the requested amount to be calculated based on the already slashed assets.
        _slash(operator2, 0.1 ether);

        // Sfrxeth is slashed by 10% so the 200 staked will be reduced to 180.
        (uint128 stakedSfrxeth,) = eigenStrategyManager.strategiesBalance(eigenStrategyManager.strategies(sfrxeth));
        assertEq(stakedSfrxeth, 180 ether, "Remaining sfrxeth staked after slashing");

        // User 1 request to withdraw all their ynEigenToken balance.
        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), type(uint256).max);
        uint256 requestTokenId = withdrawalQueueManager.requestWithdrawal(user1YnEigenTokenBalance);
        vm.stopPrank();

        // Get the arguments and queue withdrawals.
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // Wait for the withdrawal delay and complete the withdrawal.
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // Process principal withdrawals.
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        uint256 user1SfrxethBalanceBefore = sfrxeth.balanceOf(user1);

        // User1 claims the withdrawn assets.
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestTokenId, user1);

        // Check that the user received the correct amount of sfrxeth.
        assertApproxEqAbs(
            assetRegistry.convertToUnitOfAccount(wsteth, user1WstethDeposit) * 0.93 ether / 1 ether,
            assetRegistry.convertToUnitOfAccount(sfrxeth, sfrxeth.balanceOf(user1) - user1SfrxethBalanceBefore),
            0.2 ether,
            "The claimed sfrxeth should have ~93% the value of the original wsteth deposit due to slashing"
        );
    }

    function test_ReceivesSameValueOnClaimWithdraw_WithSlashing_PreQueue() public {
        uint256 user1WstethDeposit = 100 ether;
        uint256 user2SfrxethDeposit = 200 ether;

        // User 1 deposits wsteth.
        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(wsteth, user1WstethDeposit, user1);
        vm.stopPrank();

        // User 2 deposits sfrxeth.
        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(sfrxeth, user2SfrxethDeposit, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1);
        uint256[] memory singleAmount = new uint256[](1);
        
        // Stake wsteth to node 1.
        singleAsset[0] = wsteth;
        singleAmount[0] = user1WstethDeposit;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        // Stake sfrxeth to node 2.
        singleAsset[0] = sfrxeth;
        singleAmount[0] = user2SfrxethDeposit;        
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1YnEigenTokenBalance = ynEigenToken.balanceOf(user1);

        // User 1 request to withdraw all their ynEigenToken balance.
        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), type(uint256).max);
        uint256 requestTokenId = withdrawalQueueManager.requestWithdrawal(user1YnEigenTokenBalance);
        vm.stopPrank();

        // Slash 🗡️
        // Before queuing withdrawals.
        // This will cause more shares to be needed to be queued for withdraw.
        _slash(operator2, 0.1 ether);

        // Get the arguments and queue withdrawals.
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // Wait for the withdrawal delay and complete the withdrawal.
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // Process principal withdrawals.
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        uint256 user1SfrxethBalanceBefore = sfrxeth.balanceOf(user1);

        // User1 claims the withdrawn assets.
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestTokenId, user1);

        // Check that the user received the correct amount of sfrxeth.
        assertApproxEqAbs(
            assetRegistry.convertToUnitOfAccount(wsteth, user1WstethDeposit) * 0.93 ether / 1 ether,
            assetRegistry.convertToUnitOfAccount(sfrxeth, sfrxeth.balanceOf(user1) - user1SfrxethBalanceBefore),
            0.2 ether,
            "The claimed sfrxeth should have ~93% the value of the original wsteth deposit due to slashing"
        );
    }

    function test_ReceivesSameValueOnClaimWithdraw_WithSlashing_PreComplete_RevertsWithoutBuffer() public {
        uint256 user1WstethDeposit = 100 ether;
        uint256 user2SfrxethDeposit = 200 ether;

        // User 1 deposits wsteth.
        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(wsteth, user1WstethDeposit, user1);
        vm.stopPrank();

        // User 2 deposits sfrxeth.
        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(sfrxeth, user2SfrxethDeposit, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1);
        uint256[] memory singleAmount = new uint256[](1);
        
        // Stake wsteth to node 1.
        singleAsset[0] = wsteth;
        singleAmount[0] = user1WstethDeposit;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        // Stake sfrxeth to node 2.
        singleAsset[0] = sfrxeth;
        singleAmount[0] = user2SfrxethDeposit;        
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1YnEigenTokenBalance = ynEigenToken.balanceOf(user1);

        // User 1 request to withdraw all their ynEigenToken balance.
        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), type(uint256).max);
        uint256 requestTokenId = withdrawalQueueManager.requestWithdrawal(user1YnEigenTokenBalance);
        vm.stopPrank();

        // Get the arguments and queue withdrawals.
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // Slash 🗡️
        // After the withdrawals have been queued.
        // This means that less shares than expected will be withdrawn and the user can't claim what they deserve.
        _slash(operator2, 0.1 ether);

        // Wait for the withdrawal delay and complete the withdrawal.
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // Process principal withdrawals.
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        uint256 user1SfrxethBalanceBefore = sfrxeth.balanceOf(user1);

        // User1 tries to claim their withdrawal but fails because the redemption vault does not have enough assets.
        vm.expectPartialRevert(WithdrawalQueueManager.InsufficientBalance.selector);
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestTokenId, user1);
    }

    function test_ReceivesSameValueOnClaimWithdraw_WithSlashing_PreComplete() public {
        uint256 user1WstethDeposit = 100 ether;
        uint256 user2SfrxethDeposit = 200 ether;

        // User 1 deposits wsteth.
        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(wsteth, user1WstethDeposit, user1);
        vm.stopPrank();

        // User 2 deposits sfrxeth.
        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), type(uint256).max);
        ynEigenToken.deposit(sfrxeth, user2SfrxethDeposit, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1);
        uint256[] memory singleAmount = new uint256[](1);
        
        // Stake wsteth to node 1.
        singleAsset[0] = wsteth;
        singleAmount[0] = user1WstethDeposit;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        // Stake sfrxeth to node 2.
        singleAsset[0] = sfrxeth;
        singleAmount[0] = user2SfrxethDeposit;        
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1YnEigenTokenBalance = ynEigenToken.balanceOf(user1);

        // User 1 request to withdraw all their ynEigenToken balance.
        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), type(uint256).max);
        uint256 requestTokenId = withdrawalQueueManager.requestWithdrawal(user1YnEigenTokenBalance);
        vm.stopPrank();

        // Set buffer to 10%.
        vm.prank(bufferSetter);
        withdrawalsProcessor.setBuffer(1.1 ether);

        // Get the arguments and queue withdrawals.
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // Slash 🗡️
        // After the withdrawals have been queued.
        // This means that less shares than expected will be withdrawn.
        // But with the buffer set to 10%, so as long as the slashed amount is lower than this buffer, the withdrawal will still succeed.
        _slash(operator2, 0.1 ether);

        // Wait for the withdrawal delay and complete the withdrawal.
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // Process principal withdrawals.
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        uint256 user1SfrxethBalanceBefore = sfrxeth.balanceOf(user1);

        // User1 tries to claim their withdrawal.
        // Thanks to the buffer, they can claim their share.
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestTokenId, user1);

        // Check that the user received the correct amount of sfrxeth.
        assertApproxEqAbs(
            assetRegistry.convertToUnitOfAccount(wsteth, user1WstethDeposit) * 0.93 ether / 1 ether,
            assetRegistry.convertToUnitOfAccount(sfrxeth, sfrxeth.balanceOf(user1) - user1SfrxethBalanceBefore),
            0.2 ether,
            "The claimed sfrxeth should have ~93% the value of the original wsteth deposit due to slashing"
        );
    }
}
