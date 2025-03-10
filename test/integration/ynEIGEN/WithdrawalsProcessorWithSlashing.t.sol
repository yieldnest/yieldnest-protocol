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
import "forge-std/console.sol";

contract WithdrawalsProcessorWithSlashingTest is ynEigenIntegrationBaseTest {
    WithdrawalsProcessorHarness private withdrawalsProcessor;

    address private user1;
    address private user2;
    address private keeper;
    address private avs;

    ITokenStakingNode private node1;
    ITokenStakingNode private node2;

    IERC20 private wsteth;
    IERC20 private sfrxeth;

    function setUp() public virtual override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        keeper = makeAddr("keeper");
        address owner = makeAddr("owner");
        address bufferSetter = makeAddr("bufferSetter");

        wsteth = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        sfrxeth = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

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

        WithdrawalsProcessorHarness(address(withdrawalsProcessor)).initializeV2(bufferSetter, 1.1 ether);

        vm.startPrank(actors.wallets.YNSecurityCouncil);
        eigenStrategyManager.grantRole(eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor));
        eigenStrategyManager.grantRole(eigenStrategyManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor));
        withdrawalQueueManager.grantRole(withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(withdrawalsProcessor));
        vm.stopPrank();

        vm.startPrank(actors.admin.STAKING_ADMIN);
        ynEigenToken.grantRole(ynEigenToken.BURNER_ROLE(), address(withdrawalQueueManager));
        vm.stopPrank();

        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.unpauseTransfers();

        vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
        node1 = tokenStakingNodesManager.createTokenStakingNode();
        node2 = tokenStakingNodesManager.createTokenStakingNode();
        vm.stopPrank();

        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");

        ISignatureUtils.SignatureWithExpiry memory signature;
        vm.startPrank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
        node1.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, bytes32(0));
        node2.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, bytes32(0));
        vm.stopPrank();

        avs = address(new MockAVSRegistrar());

        vm.prank(avs);
        eigenLayer.allocationManager.updateAVSMetadataURI(avs, "ipfs://some-metadata-uri");

        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({ 
            operatorSetId: 1, 
            strategies: new IStrategy[](2) 
        });
        createSetParams[0].strategies[0] = eigenStrategyManager.strategies(wsteth);
        createSetParams[0].strategies[1] = eigenStrategyManager.strategies(sfrxeth);
        vm.prank(avs);
        eigenLayer.allocationManager.createOperatorSets(avs, createSetParams);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: avs,
            operatorSetIds: new uint32[](1),
            data: new bytes(0)
        });
        registerParams.operatorSetIds[0] = 1;
        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.allocationManager.registerForOperatorSets(actors.ops.TOKEN_STAKING_NODE_OPERATOR, registerParams);

        vm.roll(block.number + AllocationManagerStorage(address(eigenLayer.allocationManager)).ALLOCATION_CONFIGURATION_DELAY() + 1);

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
        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.allocationManager.modifyAllocations(actors.ops.TOKEN_STAKING_NODE_OPERATOR, allocateParams);
    }

    function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth() public {
        deal({token: address(wsteth), to: user1, give: 100 ether});
        deal({token: address(wsteth), to: user2, give: 100 ether});

        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), 100 ether);
        ynEigenToken.deposit(wsteth, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        wsteth.approve(address(ynEigenToken), 100 ether);
        ynEigenToken.deposit(wsteth, 100 ether, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1); 
        singleAsset[0] = wsteth;
        uint256[] memory singleAmount = new uint256[](1); 
        singleAmount[0] = 100 ether;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
        uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
        vm.stopPrank();

        // QUEUE WITHDRAWALS
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // COMPLETE QUEUED WITHDRAWALS
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // PROCESS PRINCIPAL WITHDRAWALS
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        // CLAIM WITHDRAWAL
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

        assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    }

    function test_FromRequestWithdrawalToClaimWithdrawal_WstethAndSfrxeth() public {
        deal({token: address(wsteth), to: user1, give: 80 ether});
        deal({token: address(sfrxeth), to: user1, give: 20 ether});
        deal({token: address(sfrxeth), to: user2, give: 50 ether});

        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), 80 ether);
        ynEigenToken.deposit(wsteth, 80 ether, user1);
        sfrxeth.approve(address(ynEigenToken), 20 ether);
        ynEigenToken.deposit(sfrxeth, 20 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        sfrxeth.approve(address(ynEigenToken), 50 ether);
        ynEigenToken.deposit(sfrxeth, 50 ether, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1); 
        singleAsset[0] = wsteth;
        uint256[] memory singleAmount = new uint256[](1); 
        singleAmount[0] = 40 ether;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        singleAsset[0] = sfrxeth;
        singleAmount[0] = 35 ether;
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
        uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
        vm.stopPrank();

        // QUEUE WITHDRAWALS
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);
        _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // COMPLETE QUEUED WITHDRAWALS
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // PROCESS PRINCIPAL WITHDRAWALS
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        // CLAIM WITHDRAWAL
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

        assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    }

    function test_FromRequestWithdrawalToClaimWithdrawal_OnlyWsteth_WithSlashing_DoesNotAffectPendingRequestedAmountIfDoneBeforeRequestWithdrawal() public {
        deal({token: address(wsteth), to: user1, give: 100 ether});
        deal({token: address(wsteth), to: user2, give: 100 ether});

        vm.startPrank(user1);
        wsteth.approve(address(ynEigenToken), 100 ether);
        ynEigenToken.deposit(wsteth, 100 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        wsteth.approve(address(ynEigenToken), 100 ether);
        ynEigenToken.deposit(wsteth, 100 ether, user2);
        vm.stopPrank();

        IERC20[] memory singleAsset = new IERC20[](1); 
        singleAsset[0] = wsteth;
        uint256[] memory singleAmount = new uint256[](1); 
        singleAmount[0] = 100 ether;
        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(node1.nodeId(), singleAsset, singleAmount);
        eigenStrategyManager.stakeAssetsToNode(node2.nodeId(), singleAsset, singleAmount);
        vm.stopPrank();

        uint256 user1BalanceBefore = wsteth.balanceOf(user1);
        uint256 ynEigenBalanceBefore = wsteth.balanceOf(address(ynEigenToken));

        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
            operatorSetId: 1,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "test"
        });
        slashingParams.strategies[0] = eigenStrategyManager.strategies(wsteth);
        // 20 wsteth of the 200 staked are slashed.
        slashingParams.wadsToSlash[0] = 0.1 ether;
        vm.prank(avs);
        eigenLayer.allocationManager.slashOperator(avs, slashingParams);

        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](2);
        nodes[0] = node1;
        nodes[1] = node2;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);

        vm.startPrank(user1);
        ynEigenToken.approve(address(withdrawalQueueManager), ynEigenToken.balanceOf(user1));
        // Requests withdrawal of all ynEIGEN 
        // - 90 wsteth are requested for withdrawal. 
        // - 20 were slashed from the whole stake, but given that user has 50%, 10 wsteth are slashed from the user balance. 
        // - Buffer adds 9 ether to withdraw, so the withdrawal would be for 99 ether
        uint256 requestWithdrawalTokenId = withdrawalQueueManager.requestWithdrawal(ynEigenToken.balanceOf(user1));
        vm.stopPrank();

        // QUEUE WITHDRAWALS
        IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
        vm.prank(keeper);
        withdrawalsProcessor.queueWithdrawals(_args);

        // COMPLETE QUEUED WITHDRAWALS
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        vm.prank(keeper);
        withdrawalsProcessor.completeQueuedWithdrawals();

        // PROCESS PRINCIPAL WITHDRAWALS
        vm.prank(keeper);
        withdrawalsProcessor.processPrincipalWithdrawals();

        // CLAIM WITHDRAWAL
        vm.prank(user1);
        withdrawalQueueManager.claimWithdrawal(requestWithdrawalTokenId, user1);

        // User claims its unslashed part.
        assertApproxEqRel(wsteth.balanceOf(user1), 89.99 ether, 0.01 ether, "wsteth balance of user1 should be 89.99");
        // The buffer part if reinvested.
        assertApproxEqRel(wsteth.balanceOf(address(ynEigenToken)), 8.99 ether, 0.01 ether, "wsteth balance of ynEigenToken should be 8.99");

        // The requested amount, given that slashing was prior to requesting, was satisfied.
        assertEq(withdrawalQueueManager.pendingRequestedRedemptionAmount(), 0, "pendingRequestedRedemptionAmount should be 0");
    }
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