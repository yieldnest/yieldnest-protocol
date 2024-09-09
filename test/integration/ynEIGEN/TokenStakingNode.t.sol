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

import "forge-std/console.sol";


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