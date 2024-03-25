// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IPausable.sol";
import {IDelegationManager} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IEigenPodManager.sol";
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {IStakingNodeV2} from "../../../src/interfaces/IStakingNodeV2.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IEigenPod.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IDelayedWithdrawalRouter.sol";
import {BeaconChainProofs} from "../../../src/external/eigenlayer/v0.2.1/BeaconChainProofs.sol";
import {TestnetEigenPodMock} from "../mocks/testnet/TestnetEigenPodMock.sol";
import {StakingNode,IStrategyManager} from "../../../src/StakingNode.sol";
import {StakingNodeTestBase} from "./StakingNode.t.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 




contract StakingNodeV2TestBase is IntegrationBaseTest {

    function setupStakingNode(uint256 depositAmount)
        public
        returns (IStakingNodeV2, IEigenPod) {

        address addr1 = vm.addr(100);

        require(depositAmount % 32 ether == 0, "depositAmount must be a multiple of 32 ether");

        uint256 validatorCount = depositAmount / 32 ether;

        vm.deal(addr1, depositAmount);

        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNodeV2 stakingNodeInstance = IStakingNodeV2(address(stakingNodesManager.createStakingNode()));

        uint256 nodeId = 0;

        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);
        for (uint256 i = 0; i < validatorCount; i++) {
            bytes memory publicKey = abi.encodePacked(uint256(i));
            publicKey = bytes.concat(publicKey, new bytes(ZERO_PUBLIC_KEY.length - publicKey.length));
            validatorData[i] = IStakingNodesManager.ValidatorData({
                publicKey: publicKey,
                signature: ZERO_SIGNATURE,
                nodeId: nodeId,
                depositDataRoot: bytes32(0)
            });
        }

        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        for (uint256 i = 0; i < validatorData.length; i++) {
            uint256 amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }
        
        bytes32 depositRoot = depositContractEth2.get_deposit_root();
        vm.prank(actors.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(depositRoot, validatorData);

        uint256 actualETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(actualETHBalance, depositAmount, "ETH balance does not match expected value");

        IEigenPod eigenPodInstance = IEigenPod(address(stakingNodeInstance.eigenPod()));

        return (stakingNodeInstance, eigenPodInstance);
    }


    modifier onlyHolesky() {
        require(block.chainid == 17000, "This test can only be run on Holesky.");
        _;
    }
}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeV2TestBase {
    using stdStorage for StdStorage;

    // function testVerifyWithdrawalCredentialsRevertingWhenPaused() public {

    //     (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

    //     MainnetEigenPodMock mainnetEigenPodMock = new MainnetEigenPodMock(eigenPodManager);

    //     address eigenPodBeaconAddress = eigenPodManager.eigenPodBeacon();
    //     address beaconOwner = Ownable(eigenPodBeaconAddress).owner();

    //     UpgradeableBeacon beacon = UpgradeableBeacon(eigenPodBeaconAddress);
    //     address previousImplementation = beacon.implementation();

    //     vm.prank(beaconOwner);
    //     beacon.upgradeTo(address(mainnetEigenPodMock));


    //     MainnetEigenPodMock(address(eigenPodInstance)).sethasRestaked(true);

    //     uint64[] memory oracleBlockNumbers = new uint64[](1);
    //     oracleBlockNumbers[0] = 0; // Mock value

    //     uint40[] memory validatorIndexes = new uint40[](1);
    //     validatorIndexes[0] = 1234567; // Validator index

    //     BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] memory proofs = new BeaconChainProofs.ValidatorFieldsAndBalanceProofs[](1);
    //     proofs[0] = BeaconChainProofs.ValidatorFieldsAndBalanceProofs({
    //         validatorFieldsProof: new bytes(0), // Mock value
    //         validatorBalanceProof: new bytes(0), // Mock value
    //         balanceRoot: bytes32(0) // Mock value
    //     });

    //     bytes32[][] memory validatorFields = new bytes32[][](1);
    //     validatorFields[0] = new bytes32[](2);
    //     validatorFields[0][0] = bytes32(0); // Mock value
    //     validatorFields[0][1] = bytes32(0); // Mock value

    //     // Note: Deposits are currently paused as per the PAUSED_DEPOSITS flag in StrategyManager.sol
    //     // See: https://github.com/Layr-Labs/eigenlayer-contracts/blob/c7bf3817c5e1430672bf8bc80558d8439a2022af/src/contracts/core/StrategyManager.sol#L168
    //     vm.expectRevert("Pausable: index is paused");
    //     vm.prank(actors.STAKING_NODES_ADMIN);
    //     stakingNodeInstance.verifyWithdrawalCredentials(oracleBlockNumbers, validatorIndexes, proofs, validatorFields);

    //     // go back to previous implementation
    //     vm.prank(beaconOwner);
    //     beacon.upgradeTo(previousImplementation);

    //     // Note: reenable this when verifyWithdrawals works
    //     // // Note: once deposits are unpaused this should work
    //     // vm.expectRevert("StrategyManager._removeShares: shareAmount too high");
    //     // stakingNodeInstance.startWithdrawal(withdrawalAmount);


    //     // // Note: once deposits are unpaused and a withdrawal is queued, it may be completed
    //     // vm.expectRevert("StrategyManager.completeQueuedWithdrawal: withdrawal is not pending");
    //     // WithdrawalCompletionParams memory params = WithdrawalCompletionParams({
    //     //     middlewareTimesIndex: 0, // Assuming middlewareTimesIndex is not used in this context
    //     //     amount: withdrawalAmount,
    //     //     withdrawalStartBlock: uint32(block.number), // Current block number as the start block
    //     //     delegatedAddress: address(0), // Assuming no delegation address is needed for this withdrawal
    //     //     nonce: 0 // first nonce is 0
    //     // });
    //     // stakingNodeInstance.completeWithdrawal(params);
    // }

    // function testCreateEigenPodReturnsEigenPodAddressAfterCreated() public {
    //     vm.prank(actors.STAKING_NODE_CREATOR);
    //     IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
    //     IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();
    //     assertEq(address(eigenPodInstance), address(stakingNodeInstance.eigenPod()));
    // }

    // function testDelegateFailWhenNotAdmin() public {
    //     vm.prank(actors.STAKING_NODE_CREATOR);
    //     IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
    //     vm.expectRevert();
    //     stakingNodeInstance.delegate(address(this));
    // }

    // function testStakingNodeDelegate() public {
    //     vm.prank(actors.STAKING_NODE_CREATOR);
    //     IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
    //     IDelegationManager delegationManager = stakingNodesManager.delegationManager();
    //     IPausable pauseDelegationManager = IPausable(address(delegationManager));
    //     vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
    //     pauseDelegationManager.unpause(0);

    //     // register as operator
    //     delegationManager.registerAsOperator(IDelegationTerms(address(this)));
    //     vm.prank(actors.STAKING_NODES_ADMIN);
    //     stakingNodeInstance.delegate(address(this));
    // }

    // function testStakingNodeUndelegate() public {
    //     vm.prank(actors.STAKING_NODE_CREATOR);
    //     IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
    //     IDelegationManager delegationManager = stakingNodesManager.delegationManager();
    //     IPausable pauseDelegationManager = IPausable(address(delegationManager));
        
    //     // Unpause delegation manager to allow delegation
    //     vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
    //     pauseDelegationManager.unpause(0);

    //     // Register as operator and delegate
    //     delegationManager.registerAsOperator(IDelegationTerms(address(this)));
    //     vm.prank(actors.STAKING_NODES_ADMIN);
    //     stakingNodeInstance.delegate(address(this));

    //     // // Attempt to undelegate
    //     vm.expectRevert();
    //     stakingNodeInstance.undelegate();

    //     IStrategyManager strategyManager = stakingNodesManager.strategyManager();
    //     uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(stakingNodeInstance));
    //     assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
    //     // Now actually undelegate with the correct role
    //     vm.prank(actors.STAKING_NODES_ADMIN);
    //     stakingNodeInstance.undelegate();
        
    //     // Verify undelegation
    //     address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
    //     assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    // }

    // function testImplementViewFunction() public {
    //     vm.prank(actors.STAKING_NODE_CREATOR);
    //     IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
    //     assertEq(stakingNodeInstance.implementation(), address(stakingNodeImplementation));
    // }

    function testVerifyWithdrawalCredentialsWithStrategyUnpausedOnHoleksy() onlyHolesky public {

        uint256 depositAmount = 32 ether;

        (IStakingNodeV2 stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        TestnetEigenPodMock testnetEigenPodMock = new TestnetEigenPodMock(IEigenPodManager(address(eigenPodManager)));

        address eigenPodBeaconAddress = eigenPodManager.eigenPodBeacon();
        address beaconOwner = Ownable(eigenPodBeaconAddress).owner();

        UpgradeableBeacon beacon = UpgradeableBeacon(eigenPodBeaconAddress);
        address previousImplementation = beacon.implementation();

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(testnetEigenPodMock));

        TestnetEigenPodMock(address(eigenPodInstance)).sethasRestaked(true);

        {
            
            uint256 oracleTimestamp = 98765;
            uint40[] memory validatorIndexes = new uint40[](1);
            validatorIndexes[0] = 1234567; // Validator index
            BeaconChainProofs.StateRootProof memory stateRootProof = BeaconChainProofs.StateRootProof({
                beaconStateRoot: bytes32(0), // Dummy value
                proof: new bytes(0) // Dummy value
            });
            bytes32[][] memory validatorFields = new bytes32[][](1);
            validatorFields[0] = new bytes32[](2);
            validatorFields[0][0] = bytes32(0); // Mock value
            validatorFields[0][1] = bytes32(0); // Mock value
            vm.prank(actors.STAKING_NODES_ADMIN);

            bytes[] memory validatorFieldsProofs = new bytes[](validatorIndexes.length);
            for(uint i = 0; i < validatorIndexes.length; i++) {
                validatorFieldsProofs[i] = bytes("dummy");
            }

            stakingNodeInstance.verifyWithdrawalCredentials(oracleTimestamp, stateRootProof, validatorIndexes, validatorFieldsProofs, validatorFields);

            // go back to previous implementation
            vm.prank(beaconOwner);
            beacon.upgradeTo(previousImplementation);
        }

        uint256 shares = strategyManager.stakerStrategyShares(address(stakingNodeInstance), stakingNodeInstance.beaconChainETHStrategy());
        assertEq(shares, depositAmount, "Shares do not match deposit amount");

    }

}
