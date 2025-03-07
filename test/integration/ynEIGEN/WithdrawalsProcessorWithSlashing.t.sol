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
    // uint256 tokenId;

    // bool private _setup = true;

    // ITokenStakingNode public tokenStakingNode;
    // IWithdrawalsProcessor public withdrawalsProcessor;

    // IStrategy private _stethStrategy;
    // IStrategy private _oethStrategy;
    // IStrategy private _sfrxethStrategy;

    // address public constant user = address(0x42069);
    // address public constant owner = address(0x42069420);
    // address public constant keeper = address(0x4206942069);
    // address public constant bufferSetter = address(0x420694206942);
    
    // uint256 AMOUNT = 50 ether;

    // function setUp() public virtual override {
    //     super.setUp();

    //     // deal assets to user
    //     {
    //         deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether});
    //         deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether});
    //         deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether});
    //     }

    //     // unpause transfers
    //     {
    //         vm.prank(actors.admin.UNPAUSE_ADMIN);
    //         ynEigenToken.unpauseTransfers();
    //     }

    //     // grant burner role
    //     {
    //         vm.startPrank(actors.admin.STAKING_ADMIN);
    //         ynEigenToken.grantRole(ynEigenToken.BURNER_ROLE(), address(withdrawalQueueManager));
    //         vm.stopPrank();
    //     }

    //     // deploy withdrawalsProcessor
    //     {
    //         withdrawalsProcessor = new WithdrawalsProcessor(
    //             address(withdrawalQueueManager),
    //             address(tokenStakingNodesManager),
    //             address(assetRegistry),
    //             address(eigenStrategyManager),
    //             address(eigenLayer.delegationManager),
    //             address(ynEigenToken),
    //             address(redemptionAssetsVault),
    //             address(wrapper),
    //             chainAddresses.lsd.STETH_ADDRESS,
    //             chainAddresses.lsd.WSTETH_ADDRESS,
    //             chainAddresses.lsd.OETH_ADDRESS,
    //             chainAddresses.lsd.WOETH_ADDRESS
    //         );

    //         withdrawalsProcessor = WithdrawalsProcessor(address(new TransparentUpgradeableProxy(address(withdrawalsProcessor), actors.admin.PROXY_ADMIN_OWNER, "")));

    //         WithdrawalsProcessor(address(withdrawalsProcessor)).initialize(owner, keeper);

    //         WithdrawalsProcessor(address(withdrawalsProcessor)).initializeV2(bufferSetter, 1 ether);
    //     }

    //     // grant roles to withdrawalsProcessor
    //     {
    //         vm.startPrank(actors.wallets.YNSecurityCouncil);
    //         eigenStrategyManager.grantRole(
    //             eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor)
    //         );
    //         eigenStrategyManager.grantRole(
    //             eigenStrategyManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor)
    //         );
    //         withdrawalQueueManager.grantRole(
    //             withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(withdrawalsProcessor)
    //         );
    //         vm.stopPrank();
    //     }

    //     // set some vars
    //     {
    //         _stethStrategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
    //         _oethStrategy = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);
    //         _sfrxethStrategy = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
    //     }
    // }

    // //
    // // queueWithdrawals
    // //
    // function testQueueWithdrawal() public {
    //     _queueWithdrawal(AMOUNT);
    // }

    // //
    // // completeQueuedWithdrawals
    // //
    // function testCompleteQueuedWithdrawals() public {
    //     _completeQueuedWithdrawals(AMOUNT);
    // }

    // //
    // // processPrincipalWithdrawals
    // //
    // function testProcessPrincipalWithdrawals() public {
    //     _processPrincipalWithdrawals(AMOUNT);
    // }

    // //
    // // claimWithdrawal
    // //
    // function testClaimWithdrawal() public {
    //     _processPrincipalWithdrawals(AMOUNT);

    //     uint256 _userStethBalanceBefore = IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user);
    //     uint256 _userSfrxethBalanceBefore = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user);

    //     _topUpRedemptionAssetsVault();

    //     vm.prank(user);
    //     withdrawalQueueManager.claimWithdrawal(tokenId, user);

    //     uint256 _expectedAmount = AMOUNT * (1_000_000 - withdrawalQueueManager.withdrawalFee()) / 1_000_000;
    //     assertApproxEqAbs(
    //         IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user),
    //         _userStethBalanceBefore + _expectedAmount,
    //         1e4,
    //         "testClaimWithdrawal: E0"
    //     );
    //     if (!_isHolesky()) {
    //         uint256 _userOethBalanceBefore = IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user);
    //         assertApproxEqAbs(
    //             IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user),
    //             _userOethBalanceBefore + _expectedAmount,
    //             1e4,
    //             "testClaimWithdrawal: E1"
    //         );
    //     }
    //     assertApproxEqAbs(
    //         IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user),
    //         _userSfrxethBalanceBefore + _expectedAmount,
    //         1e4,
    //         "testClaimWithdrawal: E2"
    //     );
    // }

    // //
    // // private helpers
    // //
    
    // function _completeQueuedWithdrawals(uint256 _amount) internal {
    //     _queueWithdrawal(_amount);

    //     // skip withdrawal delay
    //     {
    //         assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E0");
    //         vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    //     }

    //     // complete queued withdrawals -- sfrxeth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E1");

    //         vm.prank(keeper);
    //         withdrawalsProcessor.completeQueuedWithdrawals();

    //         assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), 0, "completeQueuedWithdrawals: E2");
    //         assertEq(withdrawalsProcessor.ids().completed, 1, "completeQueuedWithdrawals: E3");
    //     }

    //     // complete queued withdrawals -- steth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E4");

    //         vm.prank(keeper);
    //         withdrawalsProcessor.completeQueuedWithdrawals();

    //         assertEq(tokenStakingNode.queuedShares(_stethStrategy), 0, "completeQueuedWithdrawals: E5");
    //         assertEq(withdrawalsProcessor.ids().completed, 2, "completeQueuedWithdrawals: E6");
    //     }

    //     if (!_isHolesky()) {
    //         // complete queued withdrawals -- oeth
    //         {
    //             assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E7");

    //             vm.prank(keeper);
    //             withdrawalsProcessor.completeQueuedWithdrawals();

    //             assertEq(tokenStakingNode.queuedShares(_oethStrategy), 0, "completeQueuedWithdrawals: E8");
    //             assertEq(withdrawalsProcessor.ids().completed, 3, "completeQueuedWithdrawals: E9");
    //         }
    //     }

    //     assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E10");
    // }
    
    // function _queueWithdrawal(uint256 _amount) internal {
    //     if (_setup) setup_(_amount);

    //     uint256 _stethShares = _stethStrategy.shares((address(tokenStakingNode)));
    //     uint256 _sfrxethShares = _sfrxethStrategy.shares((address(tokenStakingNode)));
    //     uint256 _oethShares;
    //     if (!_isHolesky()) {
    //         _oethShares = _oethStrategy.shares((address(tokenStakingNode)));
    //     }

    //     bool _queuedEverything;

    //     // 1st queue withdrawals -- sfrxeth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E0");
    //         IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //         vm.prank(keeper);
    //         _queuedEverything = withdrawalsProcessor.queueWithdrawals(_args);

    //         assertFalse(_queuedEverything, "queueWithdrawal: E1");
    //         assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), _sfrxethShares, "queueWithdrawal: E2");
    //         assertEq(withdrawalsProcessor.batch(0), 1, "queueWithdrawal: E3");

    //         WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal = IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(0);
    //         assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E4");
    //         assertEq(address(_queuedWithdrawal.strategy), address(_sfrxethStrategy), "queueWithdrawal: E5");
    //         assertEq(_queuedWithdrawal.nonce, 0, "queueWithdrawal: E6");
    //         assertEq(_queuedWithdrawal.shares, _sfrxethShares, "queueWithdrawal: E7");
    //         assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E8");
    //         assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E9");
    //     }

    //     // 2nd queue withdrawals -- steth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E10");
    //         IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //         vm.prank(keeper);
    //         _queuedEverything = withdrawalsProcessor.queueWithdrawals(_args);

    //         assertTrue(_queuedEverything, "queueWithdrawal: E11");
    //         assertEq(tokenStakingNode.queuedShares(_stethStrategy), _stethShares, "queueWithdrawal: E12");
    //         assertEq(withdrawalsProcessor.batch(1), 2, "queueWithdrawal: E13");

    //         WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal = IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(1);
    //         assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E14");
    //         assertEq(address(_queuedWithdrawal.strategy), address(_stethStrategy), "queueWithdrawal: E15");
    //         assertEq(_queuedWithdrawal.nonce, 1, "queueWithdrawal: E16");
    //         assertEq(_queuedWithdrawal.shares, _stethShares, "queueWithdrawal: E17");
    //         assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E18");
    //         assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E19");
    //     }
        
    //     // 3rd queue withdrawals -- oeth
    //     {
    //         if (!_isHolesky()) {
    //             assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E20");
    //             IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
    //             vm.prank(keeper);
    //             _queuedEverything = withdrawalsProcessor.queueWithdrawals(_args);

    //             assertFalse(_queuedEverything, "queueWithdrawal: E21");
    //             assertEq(tokenStakingNode.queuedShares(_oethStrategy), _oethShares, "queueWithdrawal: E22");
    //             assertEq(withdrawalsProcessor.batch(2), 3, "queueWithdrawal: E23");

    //             WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal = IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(2);
    //             assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E24");
    //             assertEq(address(_queuedWithdrawal.strategy), address(_oethStrategy), "queueWithdrawal: E5");
    //             assertEq(_queuedWithdrawal.nonce, 2, "queueWithdrawal: E26");
    //             assertEq(_queuedWithdrawal.shares, _oethShares, "queueWithdrawal: E27");
    //             assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E28");
    //             assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E29");
    //         }
    //     }

    //     // none
    //     {
    //         WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal = IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(3);
    //         assertEq(address(_queuedWithdrawal.node), address(0), "queueWithdrawal: E25");
    //         assertEq(address(_queuedWithdrawal.strategy), address(0), "queueWithdrawal: E26");
    //         assertEq(_queuedWithdrawal.nonce, 0, "queueWithdrawal: E27");
    //         assertEq(_queuedWithdrawal.shares, 0, "queueWithdrawal: E28");
    //         assertEq(_queuedWithdrawal.startBlock, 0, "queueWithdrawal: E29");
    //         assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E30");
    //     }

    //     assertGe(
    //         withdrawalsProcessor.getTotalQueuedWithdrawals(),
    //         withdrawalQueueManager.pendingRequestedRedemptionAmount(),
    //         "queueWithdrawal: E31"
    //     );
        
    //     assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "queueWithdrawal: E32");
    // }
    
    // function _processPrincipalWithdrawals(uint256 _amount) internal {
    //     _completeQueuedWithdrawals(_amount);

    //     // process principal withdrawals -- steth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E0");

    //         vm.prank(keeper);
    //         withdrawalsProcessor.processPrincipalWithdrawals();
    //     }

    //     // process principal withdrawals -- sfrxeth
    //     {
    //         assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E1");

    //         vm.prank(keeper);
    //         withdrawalsProcessor.processPrincipalWithdrawals();
    //     }
        
    //     if (!_isHolesky()) {
    //         // process principal withdrawals -- oeth
    //         {
    //             assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E2");

    //             vm.prank(keeper);
    //             withdrawalsProcessor.processPrincipalWithdrawals();
    //         }
    //     }

    //     assertFalse(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E3");
    //     assertEq(withdrawalsProcessor.totalQueuedWithdrawals(), 0, "processPrincipalWithdrawals: E4");
    // }

    // // (1) create token staking node
    // // (2) user deposit
    // // (3) stake assets to node
    // // (4) user request withdrawal
    // function setup_(uint256 _amount) private {
    //     // create token staking node
    //     {
    //         vm.prank(actors.ops.STAKING_NODE_CREATOR);
    //         tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();
    //     }

    //     // user deposit

    //     uint256 _len = _isHolesky() ? 2 : 3;
    //     uint256[] memory _amounts = new uint256[](_len);
    //     IERC20[] memory _assetsToDeposit = new IERC20[](_len);
    //     {
    //         _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
    //         _assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
    //         if (!_isHolesky()) _assetsToDeposit[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

    //         _amounts[0] = _amount;
    //         _amounts[1] = _amount;
    //         if (!_isHolesky()) _amounts[2] = _amount;

    //         vm.startPrank(user);
    //         for (uint256 i = 0; i < _len; i++) {
    //             _assetsToDeposit[i].approve(address(ynEigenToken), _amounts[i]);
    //             ynEigenToken.deposit(_assetsToDeposit[i], _amounts[i], user);
    //         }
    //         vm.stopPrank();
    //     }

    //     // stake assets to node
    //     {
    //         vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
    //         eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), _assetsToDeposit, _amounts);
    //         vm.stopPrank();
    //     }

    //     // register operator
    //     {
    //         vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
    //         eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");
    //     }

    //     // delegate to operator
    //     {
    //         ISignatureUtils.SignatureWithExpiry memory signature;
    //         vm.prank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
    //         tokenStakingNode.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, bytes32(0));
    //     }

    //     address avs;

    //     // create AVS
    //     {
    //         avs = address(new MockAVSRegistrar());
    //     }

    //     // update metadata URI
    //     {
    //         vm.prank(avs);
    //         eigenLayer.allocationManager.updateAVSMetadataURI(avs, "ipfs://some-metadata-uri");
    //     }

    //     uint256 strategiesLength = _isHolesky() ? 2 : 3;

    //     // create operator set
    //     {
    //         IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
    //         createSetParams[0] = IAllocationManagerTypes.CreateSetParams({ 
    //             operatorSetId: 1, 
    //             strategies: new IStrategy[](strategiesLength) 
    //         });
    //         createSetParams[0].strategies[0] = _stethStrategy;
    //         createSetParams[0].strategies[1] = _sfrxethStrategy;
    //         if (!_isHolesky()) { 
    //             createSetParams[0].strategies[2] = _oethStrategy;
    //         }

    //         vm.prank(avs);
    //         eigenLayer.allocationManager.createOperatorSets(avs, createSetParams);
    //     }

    //     // register for operator set
    //     {
    //         IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
    //             avs: avs,
    //             operatorSetIds: new uint32[](1),
    //             data: new bytes(0)
    //         });
    //         registerParams.operatorSetIds[0] = 1;
    //         vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
    //         eigenLayer.allocationManager.registerForOperatorSets(actors.ops.TOKEN_STAKING_NODE_OPERATOR, registerParams);
    //     }

    //     // wait for allocation delay
    //     {
    //         vm.roll(block.number + AllocationManagerStorage(address(eigenLayer.allocationManager)).ALLOCATION_CONFIGURATION_DELAY() + 1);
    //     }

    //     // allocate
    //     {
    //         IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
    //         allocateParams[0] = IAllocationManagerTypes.AllocateParams({
    //             operatorSet: OperatorSet({
    //                 avs: avs,
    //                 id: 1
    //             }),
    //             strategies: new IStrategy[](strategiesLength),
    //             newMagnitudes: new uint64[](strategiesLength)
    //         });
    //         allocateParams[0].strategies[0] = _stethStrategy;
    //         allocateParams[0].strategies[1] = _sfrxethStrategy;
    //         allocateParams[0].newMagnitudes[0] = 1 ether;
    //         allocateParams[0].newMagnitudes[1] = 1 ether;
    //         if (!_isHolesky()) {
    //             allocateParams[0].strategies[2] = _oethStrategy;
    //             allocateParams[0].newMagnitudes[2] = 1 ether;
    //         }

    //         vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
    //         eigenLayer.allocationManager.modifyAllocations(actors.ops.TOKEN_STAKING_NODE_OPERATOR, allocateParams);
    //     }

    //     // slash
    //     // {
    //     //     IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
    //     //         operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
    //     //         operatorSetId: 1,
    //     //         strategies: new IStrategy[](strategiesLength),
    //     //         wadsToSlash: new uint256[](strategiesLength),
    //     //         description: "test"
    //     //     });
    //     //     slashingParams.strategies[0] = _stethStrategy;
    //     //     slashingParams.strategies[1] = _sfrxethStrategy;
    //     //     slashingParams.wadsToSlash[0] = 0.01 ether;
    //     //     slashingParams.wadsToSlash[1] = 0.01 ether;
    //     //     if (!_isHolesky()) {
    //     //         slashingParams.strategies[2] = _oethStrategy;
    //     //         slashingParams.wadsToSlash[2] = 0.01 ether;
    //     //     }

    //     //     vm.prank(avs);
    //     //     eigenLayer.allocationManager.slashOperator(avs, slashingParams);
    //     // }

    //     // request withdrawal
    //     {
    //         uint256 _balance = ynEigenToken.balanceOf(user);
    //         vm.startPrank(user);
    //         ynEigenToken.approve(address(withdrawalQueueManager), _balance);
    //         tokenId = withdrawalQueueManager.requestWithdrawal(_balance);
    //         vm.stopPrank();
    //     }
    // }

    // function _topUpRedemptionAssetsVault() private {
    //     address _topper = address(0x4204206969);
    //     uint256 _amount = 50; // 50 wei
    //     deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: _topper, give: _amount});
    //     deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: _topper, give: _amount});
    //     deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: _topper, give: _amount});
    //     vm.startPrank(_topper);
    //     IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
    //     redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WSTETH_ADDRESS);
    //     if (!_isHolesky()) {
    //         IERC20(chainAddresses.lsd.WOETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
    //         redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WOETH_ADDRESS);
    //     }
    //     IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
    //     redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.SFRXETH_ADDRESS);
    //     vm.stopPrank();
    // }

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

        uint256 originalBalance = wsteth.balanceOf(user1);

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

        assertApproxEqAbs(wsteth.balanceOf(user1), originalBalance, 1e4, "user1 should have approximately the original balance");
    }

    function test_FromRequestWithdrawalToClaimWithdrawal_WstethAndSfrxeth() public {
        deal({token: address(wsteth), to: user1, give: 80 ether});
        deal({token: address(sfrxeth), to: user1, give: 20 ether});
        deal({token: address(sfrxeth), to: user2, give: 50 ether});

        uint256 originalBalance = wsteth.balanceOf(user1) + sfrxeth.balanceOf(user1);

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

        assertApproxEqAbs(wsteth.balanceOf(user1) + sfrxeth.balanceOf(user1), originalBalance, 1e4, "user1 should have the original balance");
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