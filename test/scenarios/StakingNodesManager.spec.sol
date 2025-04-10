
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IntegrationBaseTest } from "test/integration/IntegrationBaseTest.sol";
import { Invariants } from "test/scenarios/Invariants.sol";
import { IStakingNodesManager } from "src/interfaces/IStakingNodesManager.sol";
import { IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";
import "forge-std/Vm.sol";

contract StakingNodesManagerScenarioTest1 is IntegrationBaseTest {

	function setUp() public override {
		super.setUp();
		// Additional setup can be added here if needed

        // setup with a max of 20 nodes
		vm.prank(actors.admin.STAKING_ADMIN);
		stakingNodesManager.setMaxNodeCount(20);
		vm.recordLogs();
	}

	/**
		Scenario 1: Successful creation of multiple Staking Nodes 
		Objective: Test that many staking nodes be created and that totalAssets()
		and other invariants hold.
	*/

	address user1 = address(0x01);
	address user2 = address(0x02);
	address user3 = address(0x03);
    uint256 totalDeposited = 0;

	function test_ynETH_Scenario_1_Multiple_Staking_Nodes(uint256 stakingNodeCount) public {
        totalDeposited = 0;

		vm.assume(stakingNodeCount > 1 && stakingNodeCount < stakingNodesManager.maxNodeCount());
		
		uint256 previousTotalDeposited = yneth.totalDepositedInPool();
		uint256 previousTotalShares = yneth.totalSupply();

		// user 1 deposits 
		uint256 user1Amount = 32 ether * stakingNodeCount;
		vm.deal(user1, user1Amount);

		uint256 user1Shares = yneth.previewDeposit(user1Amount);
        vm.prank(user1);
		yneth.depositETH{value: user1Amount}(user1);

		runInvariants(user1, previousTotalDeposited, previousTotalShares, user1Amount, user1Shares, 0);

		for (uint256 i = 0; i < stakingNodeCount; i++) {
			vm.prank(actors.ops.STAKING_NODE_CREATOR);
			stakingNodesManager.createStakingNode();
		}

        runInvariants(user1, previousTotalDeposited, previousTotalShares, user1Amount, user1Shares, 0);

        uint256[] memory validatorNodeIds = new uint256[](stakingNodeCount);
        for (uint256 i = 0; i < stakingNodeCount; i++) {
            validatorNodeIds[i] = i;
        }

        // setup 1 validator for each stakingNode
	    setupValidators(validatorNodeIds, user1Amount);

        runInvariants(user1, previousTotalDeposited, previousTotalShares, user1Amount, user1Shares, 0);

		// user deposits a second time
		uint256 user1Amount2 = 100 ether;
        vm.deal(user1, user1Amount2);
        uint256 user1Shares2 = yneth.previewDeposit(user1Amount2);
        vm.prank(user1);
		yneth.depositETH{value: user1Amount2}(user1);

        runInvariants(user1, user1Amount, user1Shares, user1Amount2, user1Shares2, 0);
        uint256 rewardsPerNode = 1 ether;
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < stakingNodeCount; i++) {
            address payable eigenPodAddress = payable(address(stakingNodesManager.nodes(i).eigenPod()));
            // deal does not trigger receive() or fallback() and emulates consensus layer rewards
            vm.deal(eigenPodAddress, rewardsPerNode);
            totalRewards += rewardsPerNode;
        }

		// balances stay the same until rewards are verified
        runInvariants(user1, user1Amount, user1Shares, user1Amount2, user1Shares2, 0);


		// TODO: verify rewards as well
	}

	function runInvariants(
	    address /* user */, 
	    uint256 previousTotalDeposited, 
	    uint256 previousTotalShares, 
	    uint256 userAmount, 
	    uint256 userShares,
        uint256 consensusLayerRewards
	) public {

		Vm.Log[] memory logs = vm.getRecordedLogs();


		for (uint256 i = 0; i < logs.length; i++) {
			Vm.Log memory log = logs[i];
			if (log.topics[0] == 
				keccak256("Deposit(address,address,uint256,uint256,uint256)")) {
				(uint256 assets,) = abi.decode(log.data, (uint256, uint256));
				totalDeposited += assets;
			}
		}

		Invariants.totalDepositIntegrity(totalDeposited, previousTotalDeposited, userAmount);
        uint256 totalNewAssets = userAmount + consensusLayerRewards;
		Invariants.totalAssetsIntegrity(yneth.totalAssets(), previousTotalDeposited, totalNewAssets);
		Invariants.shareMintIntegrity(yneth.totalSupply(), previousTotalShares, userShares);
    }

    function setupValidators(uint256[] memory validatorNodeIds, uint256 depositAmount) public {
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorNodeIds.length);
        
        for (uint256 i = 0; i < validatorNodeIds.length; i++) {
            bytes memory publicKey = abi.encodePacked(uint256(i));
            publicKey = bytes.concat(publicKey, new bytes(ZERO_PUBLIC_KEY.length - publicKey.length));
            validatorData[i] = IStakingNodesManager.ValidatorData({
                publicKey: publicKey,
                signature: ZERO_SIGNATURE,
                nodeId: validatorNodeIds[i],
                depositDataRoot: bytes32(0)
            });
        }

        for (uint256 i = 0; i < validatorData.length; i++) {
            uint256 amount = depositAmount / validatorData.length;
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }
        
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);
    }

}