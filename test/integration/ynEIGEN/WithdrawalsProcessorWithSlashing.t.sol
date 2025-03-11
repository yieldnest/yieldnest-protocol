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
    WithdrawalsProcessorHarness private withdrawalsProcessor;

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
        withdrawalsProcessor = new WithdrawalsProcessorHarness(
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
        withdrawalsProcessor = WithdrawalsProcessorHarness(address(new TransparentUpgradeableProxy(address(withdrawalsProcessor), actors.admin.PROXY_ADMIN_OWNER, "")));
        WithdrawalsProcessorHarness(address(withdrawalsProcessor)).initialize(owner, keeper);
        WithdrawalsProcessorHarness(address(withdrawalsProcessor)).initializeV2(bufferSetter, 1 ether);

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

    // function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth() public {
    //     deal({token: address(wsteth), to: user1, give: 100 ether});
    //     deal({token: address(wsteth), to: user2, give: 100 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 100 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     // QUEUE WITHDRAWALS
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    // }

    // function test_FromRequestWithdrawalToClaimWithdrawal_WstethAndSfrxeth() public {
    //     deal({token: address(wsteth), to: user1, give: 80 ether});
    //     deal({token: address(sfrxeth), to: user1, give: 20 ether});
    //     deal({token: address(sfrxeth), to: user2, give: 50 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 80 ether);
    //     ynEigenToken.deposit(wsteth, 80 ether, user1);
    //     sfrxeth.approve(address(ynEigenToken), 20 ether);
    //     ynEigenToken.deposit(sfrxeth, 20 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     sfrxeth.approve(address(ynEigenToken), 50 ether);
    //     ynEigenToken.deposit(sfrxeth, 50 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 40 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     singleAsset[0] = sfrxeth;
    //     singleAmount[0] = 35 ether;
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     // QUEUE WITHDRAWALS
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);
    //     _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    // }

    // function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth_WithSlashing_PreviousToRequest() public {
    //     deal({token: address(wsteth), to: user1, give: 100 ether});
    //     deal({token: address(wsteth), to: user2, give: 100 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 100 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
    //         operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
    //         operatorSetId: 1,
    //         strategies: new IStrategy[](1),
    //         wadsToSlash: new uint256[](1),
    //         description: "test"
    //     });
    //     slashingParams.strategies[0] = eigenStrategyManager.strategies(wsteth);
    //     // 20 wsteth of the 200 staked are slashed.
    //     slashingParams.wadsToSlash[0] = 0.1 ether;
    //     vm.prank(avs);
    //     eigenLayer.allocationManager.slashOperator(avs, slashingParams);

    //     ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
    //     nodes[0] = node1;
    //     nodes[1] = node2;
    //     eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     // Requests withdrawal of all ynEIGEN 
    //     // Given that there was slashing prior to the request. 
    //     // The pending amount would be for the user's equivalent stake minus its slashed part, resulting in 100 wsteth - 10 = 90 wsteth.
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     // QUEUE WITHDRAWALS
    //     // The buffer will add 9 wsteth the 90 requested as a buffer. Totalling 99 wsteth being queued for withdraw.
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     // User claims its unslashed part.
    //     assertApproxEqAbs(wsteth.balanceOf(user1), 89.99 ether, 0.01 ether, "wsteth balance of user1 should be 89.99");
    //     // The buffer part if reinvested.
    //     assertApproxEqAbs(wsteth.balanceOf(address(ynEigenToken)), 8.99 ether, 0.01 ether, "wsteth balance of ynEigenToken should be 8.99");

    //     // The requested amount, given that slashing was prior to requesting, was satisfied.
    //     assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    // }

    // function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth_WithSlashing_PreviousToQueueWithdrawals() public {
    //     deal({token: address(wsteth), to: user1, give: 100 ether});
    //     deal({token: address(wsteth), to: user2, give: 100 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 100 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     // Requests withdrawal of all ynEIGEN 
    //     // No slashing happened so the user will request 100 wsteth.
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
    //         operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
    //         operatorSetId: 1,
    //         strategies: new IStrategy[](1),
    //         wadsToSlash: new uint256[](1),
    //         description: "test"
    //     });
    //     slashingParams.strategies[0] = eigenStrategyManager.strategies(wsteth);
    //     // 20 wsteth of the 200 staked are slashed.
    //     slashingParams.wadsToSlash[0] = 0.1 ether;
    //     vm.prank(avs);
    //     eigenLayer.allocationManager.slashOperator(avs, slashingParams);

    //     ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
    //     nodes[0] = node1;
    //     nodes[1] = node2;
    //     eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);

    //     // QUEUE WITHDRAWALS
    //     // The user requested for 100 wsteth, so the queued amount is 100 wsteth + a buffer of 10 wsteth. Giving a total of 110 wsteth queued.
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     // 110 weth were withdrawn.
    //     // 100, which were requested, were claimed by the user, which due to slashing, receives its corresponding unslashed amount which is 90 wsteth.
    //     assertApproxEqAbs(wsteth.balanceOf(user1), 89.99 ether, 0.01 ether, "wsteth balance of user1 should be 89.99");
    //     // The buffer part which was of 10 wsteth was reinvested.
    //     assertApproxEqAbs(wsteth.balanceOf(address(ynEigenToken)), 9.99 ether, 0.01 ether, "wsteth balance of ynEigenToken should be 9.99");
    //     // While the 10 wsteth that was not claimed, remained in the vault for future withdrawals.
    //     assertApproxEqAbs(wsteth.balanceOf(address(redemptionAssetsVault)), 9.99 ether, 0.02 ether, "wsteth balance of redemptionAssetsVault should be 9.99");

    //     // The pending requested amount is the 10 wsteth that was not claimed.
    //     assertApproxEqAbs(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 10.22 ether, 0.01 ether, "pendingRequestedRedemptionAmount should be 10.22");
    // }

    // function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth_WithSlashing_PreviousToCompleteWithdrawals() public {
    //     deal({token: address(wsteth), to: user1, give: 100 ether});
    //     deal({token: address(wsteth), to: user2, give: 100 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 100 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     // Requests withdrawal of all ynEIGEN 
    //     // No slashing happened so the user will request 100 wsteth.
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     // QUEUE WITHDRAWALS
    //     // The user requested for 100 wsteth, so the queued amount is 100 wsteth + a buffer of 10 wsteth. Giving a total of 110 wsteth queued.
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
    //         operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
    //         operatorSetId: 1,
    //         strategies: new IStrategy[](1),
    //         wadsToSlash: new uint256[](1),
    //         description: "test"
    //     });
    //     slashingParams.strategies[0] = eigenStrategyManager.strategies(wsteth);
    //     // 20 wsteth of the 200 staked are slashed.
    //     slashingParams.wadsToSlash[0] = 0.1 ether;
    //     vm.prank(avs);
    //     eigenLayer.allocationManager.slashOperator(avs, slashingParams);

    //     ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
    //     nodes[0] = node1;
    //     nodes[1] = node2;
    //     eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     // 99 wsteth were withdrawn.
    //     // This is because of the 10% slashing that occured in the middle of the withdrawal.
    //     // so if 110 were being withdrawn, 10% of 110 is 11 wsteth, so 99 wsteth end up being withdrawn.
    //     // This will cover the part the user has claimed given that its stake was 50% of the total, so a 10% slash would make it have a claimeable amount of 90.
    //     assertApproxEqAbs(wsteth.balanceOf(user1), 89.99 ether, 0.01 ether, "wsteth balance of user1 should be 89.99");
    //     // Given that nothing exceeded the original pending amount, nothing could be reinvested.
    //     assertEq(wsteth.balanceOf(address(ynEigenToken)), 0, "nothing should be reinvested");
    //     // There was still an amount thanks to the buffer that remains in the redemption vault that will be used in the future.
    //     assertApproxEqAbs(wsteth.balanceOf(address(redemptionAssetsVault)), 9 ether, 0.01 ether, "wsteth balance of redemptionAssetsVault should be 9");

    //     // The pending requested amount is 9 wsteth that was not claimed plus an extra that could not be reached from the slashing.
    //     assertApproxEqAbs(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 10.22 ether, 0.01 ether, "pendingRequestedRedemptionAmount should be 10.22");
    // }

    // function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth_WithSlashing_PreviousToCompleteWithdrawals_1PercentSlash() public {
    //     deal({token: address(wsteth), to: user1, give: 100 ether});
    //     deal({token: address(wsteth), to: user2, give: 100 ether});

    //     vm.startPrank(user1);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user1);
    //     vm.stopPrank();

    //     vm.startPrank(user2);
    //     wsteth.approve(address(ynEigenToken), 100 ether);
    //     ynEigenToken.deposit(wsteth, 100 ether, user2);
    //     vm.stopPrank();

    //     IERC20[] memory singleAsset = new IERC20[](1); 
    //     singleAsset[0] = wsteth;
    //     uint256[] memory singleAmount = new uint256[](1); 
    //     singleAmount[0] = 100 ether;
    //     vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //     eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
    //     eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
    //     vm.stopPrank();

    //     vm.startPrank(user1);
    //     ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
    //     // Requests withdrawal of all ynEIGEN 
    //     // No slashing happened so the user will request 100 wsteth.
    //     uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
    //     vm.stopPrank();

    //     // QUEUE WITHDRAWALS
    //     // The user requested for 100 wsteth, so the queued amount is 100 wsteth + a buffer of 10 wsteth. Giving a total of 110 wsteth queued.
    //     IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //     vm.prank(keeper);
    //     withdrawalsProcessor.queueWithdrawals(_args);

    //     IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
    //         operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
    //         operatorSetId: 1,
    //         strategies: new IStrategy[](1),
    //         wadsToSlash: new uint256[](1),
    //         description: "test"
    //     });
    //     slashingParams.strategies[0] = eigenStrategyManager.strategies(wsteth);
    //     // 2 wsteth of the 200 staked are slashed.
    //     slashingParams.wadsToSlash[0] = 0.01 ether;
    //     vm.prank(avs);
    //     eigenLayer.allocationManager.slashOperator(avs, slashingParams);

    //     ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
    //     nodes[0] = node1;
    //     nodes[1] = node2;
    //     eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);

    //     // COMPLETE QUEUED WITHDRAWALS
    //     vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     vm.prank(keeper);
    //     withdrawalsProcessor.completeQueuedWithdrawals();

    //     // PROCESS PRINCIPAL WITHDRAWALS
    //     vm.prank(keeper);
    //     withdrawalsProcessor.processPrincipalWithdrawals();

    //     // CLAIM WITHDRAWAL
    //     vm.prank(user1);
    //     withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

    //     // 108.9 wsteth were withdrawn.
    //     // This is because of the 1% slashing that occured in the middle of the withdrawal.
    //     // so if 110 were being withdrawn, 1% of 110 is 1.1 wsteth, so 108.9 wsteth end up being withdrawn.
    //     // This will cover the part the user has claimed given that its stake was 50% of the total, so a 1% slash would make it have a claimeable amount of 99.
    //     assertApproxEqAbs(wsteth.balanceOf(user1), 98.99 ether, 0.01 ether, "wsteth balance of user1 should be 98.99");
    //     // 100 was originally requested by 108.9 wsteth were withdrawn, so 8.9 wsteth have to be reinvested.
    //     assertApproxEqAbs(wsteth.balanceOf(address(ynEigenToken)), 8.89 ether, 0.02 ether, "wsteth balance of ynEigenToken should be 8.89");
    //     // 1 wsteth was not claimed and was left in the vault for future withdrawals.
    //     assertApproxEqAbs(wsteth.balanceOf(address(redemptionAssetsVault)), 1 ether, 0.01 ether, "wsteth balance of redemptionAssetsVault should be 1");

    //     // The pending requested amount is 1 wsteth that was not claimed plus an extra that could not be reached from the slashing.
    //     assertApproxEqAbs(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 1.02 ether, 0.01 ether, "pendingRequestedRedemptionAmount should be 1.02");
    // }
}

contract WithdrawalsProcessorHarness is WithdrawalsProcessor {
    constructor(
        address _withdrawalQueueManager,
        address _tokenStakingNodesManager,
        address _assetRegistry,
        address _ynStrategyManager,
        address _delegationManager,
        address _yneigen,
        address _redemptionAssetsVault,
        address _wrapper,
        address _steth,
        address _wsteth,
        address _oeth,
        address _woeth
    )
        WithdrawalsProcessor(
            _withdrawalQueueManager,
            _tokenStakingNodesManager,
            _assetRegistry,
            _ynStrategyManager,
            _delegationManager,
            _yneigen,
            _redemptionAssetsVault,
            _wrapper,
            _steth,
            _wsteth,
            _oeth,
            _woeth
        )
    {}

    function sharesToUnit(uint256 _shares, IERC20 _asset, IStrategy _strategy) external view returns (uint256) {
        return _sharesToUnit(_shares, _asset, _strategy);
    }

    function applyBuffer(uint256 _amount) external view returns (uint256) {
        return _applyBuffer(_amount);
    }

    function unitToShares(uint256 _amount, IERC20 _asset, IStrategy _strategy) external view returns (uint256) {
        return _unitToShares(_amount, _asset, _strategy);
    }
}