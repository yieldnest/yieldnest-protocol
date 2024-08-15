// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {LSDStakingNode} from "src/LSDStakingNode.sol";
import {IStrategyManager}	from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {IynLSD} from "src/interfaces/IynLSD.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";

contract LSDStakingNodeTest is IntegrationBaseTest {

	ILSDStakingNode lsdStakingNode;

	function setUp() public override {
		super.setUp();
		vm.prank(actors.ops.STAKING_NODE_CREATOR);
		lsdStakingNode = ynlsd.createLSDStakingNode();
	}
	
	function testYnLSDView() public {
		IynLSD _ynlsd = lsdStakingNode.ynLSD();
		assertEq(address(_ynlsd), address(ynlsd));
	}

	function testNodeIdView() public {
		uint256 _nodeId = lsdStakingNode.nodeId();
		assertEq(_nodeId, 0);
	}

	function testImplementationView() public {
		address _implementation = lsdStakingNode.implementation();
		vm.prank(actors.ops.STAKING_NODE_CREATOR);
		ynlsd.createLSDStakingNode();
		ILSDStakingNode _lsdStakingNode = ynlsd.nodes(0);
		assertEq(_implementation, address(_lsdStakingNode.implementation()));
	}

	function testDepositAssetsToEigenlayerSuccess() public {
		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), 0.01 ether);
		stETH.approve(address(ynlsd), balance);
		ynlsd.deposit(stETH, balance, address(this));

		// 2. Deposit assets to Eigenlayer by LSD ReStaking Manager
        IPausable pausableStrategyManager = IPausable(address(strategyManager));
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();
        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

		IERC20[] memory assets = new IERC20[](1);
		assets[0] = stETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 1 ether;
		vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
		(, uint256[] memory deposits) = strategyManager.getDeposits(address(lsdStakingNode));
		assertGt(deposits[0], 1);
	}

	function testDepositAssetsToEigenlayerFail() public {

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), 0.01 ether);
		stETH.approve(address(ynlsd), balance);
		ynlsd.deposit(stETH, balance, address(this));

		// 2. Deposit should fail when paused
        IStrategyManager strategyManager = ynlsd.strategyManager();
        vm.prank(chainAddresses.eigenlayer.STRATEGY_MANAGER_PAUSER_ADDRESS);
        IPausable(address(strategyManager)).pause(1);
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = stETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = balance;
		vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
		vm.expectRevert("Pausable: index is paused");
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
	}
}


contract LSDStakingNodeDelegate is IntegrationBaseTest {
	// function testLSDStakingNodeDelegate() public {
  //       vm.prank(actors.ops.STAKING_NODE_CREATOR);
  //       ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();
  //       IDelegationManager delegationManager = ynlsd.delegationManager();

  //       IPausable pauseDelegationManager = IPausable(address(delegationManager));
  //       vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
  //       pauseDelegationManager.unpause(0);

  //       // register as operator
  //       delegationManager.registerAsOperator(
  //           IDelegationManager.OperatorDetails({
  //               earningsReceiver: address(this),
  //               delegationApprover: address(0),
  //               stakerOptOutWindowBlocks: 1
  //           }), 
  //           "ipfs://some-ipfs-hash"
  //       );

	// 			ISignatureUtils.SignatureWithExpiry memory signature;
	// 			bytes32 approverSalt;

	// 			vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
  //       lsdStakingNodeInstance.delegate(address(this), signature, approverSalt);
  //   }

    // function testLSDStakingNodeUndelegate() public {
    //     vm.prank(actors.ops.STAKING_NODE_CREATOR);
    //     ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();
    //     IDelegationManager delegationManager = ynlsd.delegationManager();
    //     IPausable pauseDelegationManager = IPausable(address(delegationManager));
        
    //     // Unpause delegation manager to allow delegation
    //     vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
    //     pauseDelegationManager.unpause(0);

    //     // Register as operator and delegate
    //     delegationManager.registerAsOperator(
    //         IDelegationManager.OperatorDetails({
    //             earningsReceiver: address(this),
    //             delegationApprover: address(0),
    //             stakerOptOutWindowBlocks: 1
    //         }), 
    //         "ipfs://some-ipfs-hash"
    //     );
				
		// 		vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
		// 		ISignatureUtils.SignatureWithExpiry memory signature;
		// 		bytes32 approverSalt;

    //     lsdStakingNodeInstance.delegate(address(this), signature, approverSalt);

    //     // Attempt to undelegate
    //     vm.expectRevert();
    //     lsdStakingNodeInstance.undelegate();

    //     IStrategyManager strategyManager = ynlsd.strategyManager();
    //     uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(lsdStakingNodeInstance));
    //     assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
    //     // Now actually undelegate with the correct role
    //     vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
    //     lsdStakingNodeInstance.undelegate();
        
    //     // Verify undelegation
    //     address delegatedAddress = delegationManager.delegatedTo(address(lsdStakingNodeInstance));
    //     assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    // }

	function testRecoverDirectDeposits() public {
		// setup
		vm.prank(actors.ops.STAKING_NODE_CREATOR);
		ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();
		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), 0.01 ether);
		uint256 ynLSDBalanceBefore = stETH.balanceOf(address(ynlsd));

		// transfer steth to the staking node
		stETH.approve(address(lsdStakingNodeInstance), balance);
		stETH.transfer(address(lsdStakingNodeInstance), balance);

		// recover the stuck steth in the staking node
		vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
		lsdStakingNodeInstance.recoverAssets(IERC20(chainAddresses.lsd.STETH_ADDRESS));
		stETH.balanceOf(address(ynlsd));
		assertEq(
			compareWithThreshold(
				stETH.balanceOf(address(ynlsd)) - ynLSDBalanceBefore, 
				balance, 
				2
			),
			true
		);
	}
}