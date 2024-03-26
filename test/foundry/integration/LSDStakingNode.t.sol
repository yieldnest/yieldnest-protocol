// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./IntegrationBaseTest.sol";

import {ILSDStakingNode} from "../../../src/interfaces/ILSDStakingNode.sol";
import {IynLSD} from "../../../src/interfaces/IynLSD.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IPausable.sol";
import {IDelegationTerms} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelegationTerms.sol";


contract LSDStakingNodeTest is IntegrationBaseTest {

	ILSDStakingNode lsdStakingNode;

	function setUp() public override {
		super.setUp();
		vm.prank(actors.STAKING_NODE_CREATOR);
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
		vm.prank(actors.STAKING_NODE_CREATOR);
		ynlsd.createLSDStakingNode();
		ILSDStakingNode _lsdStakingNode = ynlsd.nodes(0);
		assertEq(_implementation, address(_lsdStakingNode.implementation()));
	}

	function testDepositAssetsToEigenlayerUnsupportedAsset() public {
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = IERC20(address(ynlsd));
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 100;
		vm.prank(actors.LSD_RESTAKING_MANAGER);
		vm.expectRevert(abi.encodeWithSelector(LSDStakingNode.UnsupportedAsset.selector, assets[0]));
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
	}

	function testDepositAssetsToEigenlayerSuccess() public {

		// 1. Obtain stETH and Deposit assets to ynLSD by User
		IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
        assertEq(compareWithThreshold(balance, amount, 1), true, "Amount not received");
		stETH.approve(address(ynlsd), amount);
		ynlsd.deposit(stETH, amount, address(this));

		// 2. Deposit assets to Eigenlayer by LSD ReStaking Manager
        IPausable pausableStrategyManager = IPausable(address(strategyManager));
        vm.prank(actors.STAKING_NODE_CREATOR);
        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();
        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

		IERC20[] memory assets = new IERC20[](1);
		assets[0] = stETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 1 ether;
		vm.prank(actors.LSD_RESTAKING_MANAGER);
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
		(, uint256[] memory deposits) = strategyManager.getDeposits(address(lsdStakingNode));
		assertGt(deposits[0], 1);
	}

	function testDepositAssetsToEigenlayerFail() public {

		// 1. Obtain stETH and Deposit assets to ynLSD by User
		IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
		stETH.approve(address(ynlsd), balance);
		ynlsd.deposit(stETH, balance, address(this));

		// 2. Deposit should fail when paused
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = stETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 1 ether;
		vm.prank(actors.LSD_RESTAKING_MANAGER);
		vm.expectRevert("Pausable: index is paused");
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
	}
}


contract LSDStakingNodeDelegate is IntegrationBaseTest {
	function testLSDStakingNodeDelegate() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();
        IDelegationManager delegationManager = ynlsd.delegationManager();

        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        // register as operator
        delegationManager.registerAsOperator(IDelegationTerms(address(this)));
        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNodeInstance.delegate(address(this));
    }

    function testLSDStakingNodeUndelegate() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();
        IDelegationManager delegationManager = ynlsd.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        
        // Unpause delegation manager to allow delegation
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        // Register as operator and delegate
        delegationManager.registerAsOperator(IDelegationTerms(address(this)));
        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNodeInstance.delegate(address(this));

        // // Attempt to undelegate
        vm.expectRevert();
        lsdStakingNodeInstance.undelegate();

        IStrategyManager strategyManager = ynlsd.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(lsdStakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
        // Now actually undelegate with the correct role
        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNodeInstance.undelegate();
        
        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(lsdStakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }
}