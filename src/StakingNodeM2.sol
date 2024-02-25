pragma solidity ^0.8.24;

import {IDelegationManager as IDelegationManagerM2 } from "./interfaces/eigenlayer/IDelegationManager.sol";
import {IEigenPod as IEigenPodM2 } from "./interfaces/eigenlayer/IEigenPod.sol";
import {ISignatureUtils} from "./interfaces/eigenlayer/ISignatureUtils.sol";
import { BeaconChainProofs as BeaconChainProofsM2 } from "./external/eigenlayer/BeaconChainProofs.sol";
import {IStrategy as IStrategyM2} from "./interfaces/eigenlayer/IStrategy.sol";

import "./StakingNode.sol";


/*
    The purpose of this file, StakingNodeM2.sol, is to extend the functionality of the StakingNode contract
    specifically for the M2 deployment on EigenLayer that is currently operational on the Goerli testnet.
    This deployment aims to address and integrate with the unique features and requirements of the EigenLayer M2,
    including enhanced delegation management, withdrawal credential verification, and validator management,
    tailored to the EigenLayer's specifications and protocols.

    Release:

    https://github.com/Layr-Labs/eigenlayer-contracts/releases/tag/v0.2.1-goerli-m2

    For more detailed information and updates, refer to the GitHub release at:
    https://github.com/Layr-Labs/eigenlayer-contracts/releases/

*/

contract StakingNodeM2 is StakingNode {

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSIT AND DELEGATION   -------------------------
    //--------------------------------------------------------------------------------------


    function delegate(address operator) public override onlyAdmin {

        IDelegationManagerM2 delegationManager = IDelegationManagerM2(address(stakingNodesManager.delegationManager()));

        // Only supports empty approverSignatureAndExpiry and approverSalt
        // this applies when no IDelegationManager.OperatorDetails.delegationApprover is specified by operator
        // TODO: add support for operators that require signatures
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        bytes32 approverSalt;

        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit Delegated(operator, approverSalt);
    }

    /// @dev Validates the withdrawal credentials for a withdrawal
    /// This activates the activation of the staked funds within EigenLayer
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        IEigenPodM2.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    ) external onlyAdmin {
        IEigenPodM2(address(eigenPod)).verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            withdrawalCredentialProofs,
            validatorFields
        );

        for (uint i = 0; i < validatorIndices.length; i++) {

            // TODO: check if this is correct
            uint64 validatorBalanceGwei = BeaconChainProofsM2.getEffectiveBalanceGwei(validatorFields[i]);

            allocatedETH -= (validatorBalanceGwei * 1e9);
        }
    }

    function verifyWithdrawalCredentials(
        uint64[] calldata oracleBlockNumber,
        uint40[] calldata validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] calldata proofs,
        bytes32[][] calldata validatorFields
    ) external override {
        // the https://github.com/Layr-Labs/eigenlayer-contracts/releases/tag/mainnet-deployment
        // withdrawal path. Will no longer be supported.
        revert("StakingNode: Sunset functionality");
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL AND UNDELEGATION   --------------------
    //--------------------------------------------------------------------------------------


    /*
    *  Withdrawal Flow:
    *
    *  1. queueWithdrawals() - Admin queues withdrawals
    *  2. undelegate() - Admin undelegates
    *  3. verifyAndProcessWithdrawals() - Admin verifies and processes withdrawals
    *  4. completeWithdrawal() - Admin completes withdrawal
    *
    */

    function queueWithdrawals(uint shares) public onlyAdmin {
    
        IDelegationManagerM2 delegationManager = IDelegationManagerM2(address(stakingNodesManager.delegationManager()));

        IDelegationManagerM2.QueuedWithdrawalParams[] memory queuedWithdrawalParams = new IDelegationManagerM2.QueuedWithdrawalParams[](1);
        queuedWithdrawalParams[0] = IDelegationManagerM2.QueuedWithdrawalParams({
            strategies: new IStrategyM2[](1),
            shares: new uint256[](1),
            withdrawer: address(this)
        });
        queuedWithdrawalParams[0].strategies[0] = IStrategyM2(address(beaconChainETHStrategy));
        queuedWithdrawalParams[0].shares[0] = shares;
        
        delegationManager.queueWithdrawals(queuedWithdrawalParams);
    }

    function undelegate() public onlyAdmin {
        
        IDelegationManagerM2 delegationManager = IDelegationManagerM2(address(stakingNodesManager.delegationManager()));
        delegationManager.undelegate(address(this));
    }

    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        IEigenPodM2.StateRootProof calldata stateRootProof,
        IEigenPodM2.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external onlyAdmin {
    
        IEigenPodM2(address(eigenPod)).verifyAndProcessWithdrawals(
            oracleTimestamp,
            stateRootProof,
            withdrawalProofs,
            validatorFieldsProofs,
            validatorFields,
            withdrawalFields
        );
    }

    function completeWithdrawal(
        uint shares,
        uint32 startBlock
    ) external onlyAdmin {

        IDelegationManagerM2 delegationManager = IDelegationManagerM2(address(stakingNodesManager.delegationManager()));

        uint[] memory sharesArray = new uint[](1);
        sharesArray[0] = shares;

        IStrategyM2[] memory strategiesArray = new IStrategyM2[](1);
        strategiesArray[0] = IStrategyM2(address(beaconChainETHStrategy));

        IDelegationManagerM2.Withdrawal memory withdrawal = IDelegationManagerM2.Withdrawal({
            staker: address(this),
            delegatedTo: delegationManager.delegatedTo(address(this)),
            withdrawer: address(this),
            nonce: 0, // TODO: fix
            startBlock: startBlock,
            strategies: strategiesArray,
            shares:  sharesArray
        });

        uint256 balanceBefore = address(this).balance;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(0x0000000000000000000000000000000000000000);

        // middlewareTimesIndexes is 0, since it's unused
        // https://github.com/Layr-Labs/eigenlayer-contracts/blob/5fd029069b47bf1632ec49b71533045cf00a45cd/src/contracts/core/DelegationManager.sol#L556
        delegationManager.completeQueuedWithdrawal(withdrawal, tokens, 0, true);

        uint256 balanceAfter = address(this).balance;
        uint256 fundsWithdrawn = balanceAfter - balanceBefore;

        stakingNodesManager.processWithdrawnETH{value: fundsWithdrawn}(nodeId);
    }
}
