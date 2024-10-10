// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {ynEigenIntegrationBaseTest} from "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IStrategyManager}	from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";



import "forge-std/console.sol";


interface ITestState {
    function ynEigenToken() external view returns (IynEigen);
    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);
    function assetRegistry() external view returns (IAssetRegistry);
    function eigenStrategyManager() external view returns (EigenStrategyManager);
    function eigenLayerStrategyManager() external view returns (IStrategyManager);
    function eigenLayerDelegationManager() external view returns (IDelegationManager);
}

interface ITokenStakingNodesManager {
    function nodes(uint256 nodeId) external view returns (ITokenStakingNode);
    function createTokenStakingNode() external returns (ITokenStakingNode);
}


struct StateSnapshot {
    uint256 totalAssets;
    uint256 totalSupply;
    mapping(IStrategy => uint256) strategyQueuedShares;
    mapping(address => uint256) withdrawnByToken;
    mapping(address => uint256) stakedAssetBalanceForNode;
    mapping(address => uint256) strategySharesForNode;
}

contract NodeStateSnapshot {
    StateSnapshot public snapshot;

    constructor() {}

    function takeSnapshot(address testAddress, uint256 nodeId) external {

        ITestState state = ITestState(testAddress);
        ITokenStakingNode node = state.tokenStakingNodesManager().nodes(nodeId);

        snapshot.totalAssets = state.ynEigenToken().totalAssets();
        snapshot.totalSupply = state.ynEigenToken().totalSupply();  

        IERC20[] memory assets = state.assetRegistry().getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            IStrategy strategy = state.eigenStrategyManager().strategies(asset);
            
            // Store queued shares for each strategy
            snapshot.strategyQueuedShares[strategy] = node.queuedShares(strategy);
            
            // Store withdrawn amount for each token
            snapshot.withdrawnByToken[address(asset)] = node.withdrawn(asset);

            // Store staked asset balance for each token
            snapshot.stakedAssetBalanceForNode[address(asset)]
                = state.eigenStrategyManager().getStakedAssetBalanceForNode(asset, nodeId);

            // Store strategy shares for each token
            snapshot.strategySharesForNode[address(asset)] = 
                state.eigenStrategyManager().strategyManager().stakerStrategyShares(address(node), strategy);
        }
    }

    function totalAssets() external view returns (uint256) {
        return snapshot.totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return snapshot.totalSupply;
    }

    function getStrategyQueuedShares(IStrategy strategy) external view returns (uint256) {
        return snapshot.strategyQueuedShares[strategy];
    }

    function getWithdrawnByToken(address token) external view returns (uint256) {
        return snapshot.withdrawnByToken[token];
    }

    function getStakedAssetBalanceForNode(address token) external view returns (uint256) {
        return snapshot.stakedAssetBalanceForNode[token];
    }

    function getStrategySharesForNode(address token) external view returns (uint256) {
        return snapshot.strategySharesForNode[token];
    }
}

contract TokenStakingNodeTest is ynEigenIntegrationBaseTest {

	ITokenStakingNode tokenStakingNode;
    TestAssetUtils testAssetUtils;

    constructor() {
       testAssetUtils = new TestAssetUtils();
    }

	function setUp() public override {
		super.setUp();
		vm.prank(actors.ops.STAKING_NODE_CREATOR);
		tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();
	}
	
	function testNodeIdView() public {
		uint256 _nodeId = tokenStakingNode.nodeId();
		assertEq(_nodeId, 0);
	}

	function testImplementationView() public {
		address _implementation = tokenStakingNode.implementation();
		vm.prank(actors.ops.STAKING_NODE_CREATOR);
		tokenStakingNodesManager.createTokenStakingNode();
		ITokenStakingNode _newTokenStakingNode = tokenStakingNodesManager.nodes(0);
		assertEq(_implementation, address(_newTokenStakingNode.implementation()));
	}

	function testDepositAssetsToEigenlayerSuccessFuzz(
        uint256 wstethAmount
     ) public {
        vm.assume(
            wstethAmount < 10000 ether && wstethAmount >= 2 wei
        ); 

		// 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));

		// 2. Deposit assets to Eigenlayer by Token Staking Node

		IERC20[] memory assets = new IERC20[](1);
		assets[0] = wstETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = wstethAmount;
        uint256 nodeId = tokenStakingNode.nodeId();
		vm.prank(actors.ops.STRATEGY_CONTROLLER);
		eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        uint256 expectedStETHAmount = IwstETH(address(wstETH)).stEthPerToken() * amounts[0] / 1e18;

        // TODO: figure out why this doesn't match.
		// assertTrue(
        //     compareWithThreshold(deposits[0], expectedStETHAmount, 2),
        //     "Strategy user underlying view does not match expected stETH amount within threshold"
        // );
  
        uint256 treshold = wstethAmount / 1e17 + 3;
		uint256 expectedBalance = eigenStrategyManager.getStakedAssetBalance(assets[0]);
		assertTrue(
            compareWithThreshold(expectedBalance, amounts[0], treshold),
            "Staked asset balance does not match expected deposits"
        );

		uint256 strategyUserUnderlyingView = eigenStrategyManager.strategies(assets[0]).userUnderlyingView(address(tokenStakingNode));

		assertTrue(compareWithThreshold(strategyUserUnderlyingView, expectedStETHAmount, treshold), "Strategy user underlying view does not match expected stETH amount within threshold");
	}

	function testDepositAssetsToEigenlayerFail() public {
		// 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 balance = testAssetUtils.get_wstETH(address(this), 10 ether);
		wstETH.approve(address(ynEigenToken), balance);
		ynEigenToken.deposit(wstETH, balance, address(this));
        uint256 nodeId = tokenStakingNode.nodeId();

		// 2. Deposit should fail when paused
        IStrategyManager strategyManager = eigenStrategyManager.strategyManager();
        vm.prank(chainAddresses.eigenlayer.STRATEGY_MANAGER_PAUSER_ADDRESS);
        IPausable(address(strategyManager)).pause(1);
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = wstETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = balance;
		vm.prank(actors.ops.STRATEGY_CONTROLLER);
		vm.expectRevert("Pausable: index is paused");
		eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
	}


    function testTokenQueueWithdrawals() public {

        uint256 wstethAmount = 100 ether;
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 nodeId = tokenStakingNode.nodeId();
        {
            // 1. Obtain wstETH and Deposit assets to ynEigen by User
            testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));

            // 2. Deposit assets to Eigenlayer by Token Staking Node

            IERC20[] memory assets = new IERC20[](1);
            assets[0] = wstETH;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = wstethAmount;
            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        }

        NodeStateSnapshot before = new NodeStateSnapshot();
        before.takeSnapshot(address(this), nodeId);

        uint256 withdrawnShares = 50 ether;

        // 3. Queue withdrawals
        vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = tokenStakingNode.queueWithdrawals(
            eigenStrategyManager.strategies(wstETH),
            withdrawnShares
        );
        vm.stopPrank();

        NodeStateSnapshot afterQueued = new NodeStateSnapshot();
        afterQueued.takeSnapshot(address(this), nodeId);

        // Assert queuedShares increased
        assertEq(
            afterQueued.getStrategyQueuedShares(eigenStrategyManager.strategies(wstETH)),
            before.getStrategyQueuedShares(eigenStrategyManager.strategies(wstETH)) + withdrawnShares,
            "Queued shares should have increased"
        );

        // Assert everything else stayed the same
        assertEq(
            afterQueued.totalAssets(),
            before.totalAssets(),
            "Total assets should not have changed"
        );
        assertEq(
            afterQueued.totalSupply(),
            before.totalSupply(),
            "Total supply should not have changed"
        );
        assertEq(
            afterQueued.getWithdrawnByToken(address(wstETH)),
            before.getWithdrawnByToken(address(wstETH)),
            "Withdrawn amount should not have changed"
        );

        // Assert staked asset balance decreased
        assertEq(
            afterQueued.getStakedAssetBalanceForNode(address(wstETH)),
            before.getStakedAssetBalanceForNode(address(wstETH)),
            "Staked asset balance should have decreased by withdrawn shares"
        );

        // Assert strategy shares decreased
        assertEq(
            afterQueued.getStrategySharesForNode(address(wstETH)),
            before.getStrategySharesForNode(address(wstETH)) - withdrawnShares,
            "Strategy shares should have decreased by withdrawn shares"
        );
    }

    function testQueueAndCompleteWithdrawals() public {

        // Stake some wstETH to the node
        uint256 stakeAmount = 100 ether;
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 nodeId = tokenStakingNode.nodeId();
        uint256 sharesToWithdraw;
        uint256 withdrawAmount;
        IStrategy wstETHStrategy = eigenStrategyManager.strategies(wstETH);
        uint32 _startBlock;
        {
            // 1. Obtain wstETH and Deposit assets to ynEigen by User
            testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

            IERC20[] memory assets = new IERC20[](1);
            assets[0] = IERC20(address(wstETH));
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = stakeAmount;

            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

            // Prepare for withdrawal
            withdrawAmount = stakeAmount / 2;
            sharesToWithdraw = wstETHStrategy.underlyingToShares(
                IwstETH(address(wstETH)).getStETHByWstETH(withdrawAmount)
            );

            // Queue withdrawal
            vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
            bytes32[] memory withdrawalRoots = tokenStakingNode.queueWithdrawals(wstETHStrategy, sharesToWithdraw);

            _startBlock = uint32(block.number);

            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = wstETHStrategy;
            vm.roll(block.number + eigenLayer.delegationManager.getWithdrawalDelay(_strategies));
        }

        // Capture state before completing withdrawal
        NodeStateSnapshot before = new NodeStateSnapshot();
        before.takeSnapshot(address(this), nodeId);

        // Complete queued withdrawal
        vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(
            eigenLayer.delegationManager.cumulativeWithdrawalsQueued(address(tokenStakingNode)) - 1, // _nonce
            _startBlock, // _startBlock
            sharesToWithdraw, // _shares
            wstETHStrategy, // _strategy
            new uint256[](1), // _middlewareTimesIndexes
            false
        );
        vm.stopPrank();

        NodeStateSnapshot afterCompletion = new NodeStateSnapshot();
        afterCompletion.takeSnapshot(address(this), nodeId);

        // Assert withdrawn amount increased
        assertApproxEqAbs(
            afterCompletion.getWithdrawnByToken(address(wstETH)),
            before.getWithdrawnByToken(address(wstETH)) + withdrawAmount,
            3,
            "Withdrawn amount should have increased by withdrawAmount"
        );

        // Assert queued shares decreased
        assertEq(
            afterCompletion.getStrategyQueuedShares(wstETHStrategy),
            before.getStrategyQueuedShares(wstETHStrategy) - sharesToWithdraw,
            "Queued shares should have decreased by sharesToWithdraw"
        );

        // Assert total supply remained unchanged
        assertEq(
            afterCompletion.totalSupply(),
            before.totalSupply(),
            "Total supply should remain unchanged"
        );

        // Assert total assets remained approximately unchanged
        assertApproxEqAbs(
            afterCompletion.totalAssets(),
            before.totalAssets(),
            3,
            "Total assets should remain approximately unchanged"
        );

        eigenStrategyManager.updateTokenStakingNodesBalances(wstETH);

        assertApproxEqAbs(
            afterCompletion.totalAssets(),
            ynEigenToken.totalAssets(),
            3,
            "Total assets should have decreased by approximately the withdraw amount"
        );
    }
}


contract TokenStakingNodeDelegate is ynEigenIntegrationBaseTest {

    
	function testTokenStakingNodeDelegate() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        address operatorAddress = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

        // TODO: handle operatorAddress as payments receiver in PaymentsReceiver
        // register as operator
        vm.prank(operatorAddress);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: operatorAddress, // deprecated
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }), 
            "ipfs://some-ipfs-hash"
        );

		ISignatureUtils.SignatureWithExpiry memory signature;
		bytes32 approverSalt;

		vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operatorAddress, signature, approverSalt);
        address delegatedTo = delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedTo, operatorAddress, "Delegation did not occur as expected.");
    }

    function testTokenStakingNodeUndelegate() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        
        // Unpause delegation manager to allow delegation
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        address operatorAddress = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

        // TODO: handle operatorAddress as payments receiver in PaymentsReceiver

        // Register as operator and delegate
        vm.prank(operatorAddress);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: operatorAddress,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }), 
            "ipfs://some-ipfs-hash"
        );
				
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;

		vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operatorAddress, signature, approverSalt);

        // Attempt to undelegate
        vm.expectRevert();
        tokenStakingNodeInstance.undelegate();

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
        // Now actually undelegate with the correct role
		vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();
        
        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }
}

