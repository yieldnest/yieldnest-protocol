pragma solidity ^0.8.24;

import {IDelegationManager as IDelegationManagerV02 } from "../../../src/external/eigenlayer/v0.2.1/interfaces/IDelegationManager.sol";
import {IEigenPod as IEigenPodV02 } from "../../../src/external/eigenlayer/v0.2.1/interfaces/IEigenPod.sol";
import {BeaconChainProofs as BeaconChainProofsV02} from "../../../src/external/eigenlayer/v0.2.1/BeaconChainProofs.sol";
import {ISignatureUtils} from "../../../src/external/eigenlayer/v0.2.1/interfaces/ISignatureUtils.sol";
import {BeaconChainProofs as BeaconChainProofsV02} from "../../../src/external/eigenlayer/v0.2.1/BeaconChainProofs.sol";
import {IStrategy as IStrategyV02} from "../../../src/external/eigenlayer/v0.2.1/interfaces/IStrategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StakingNode} from "../../../src/StakingNode.sol";

/**
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
contract StakingNodeV2 is StakingNode {

    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates the staking operation to a specified operator.
     * @param operator The address of the operator to whom the staking operation is being delegated.
     */
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public onlyAdmin {

        IDelegationManagerV02 delegationManager = IDelegationManagerV02(address(stakingNodesManager.delegationManager()));
        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit Delegated(operator, approverSalt);
    }


    /**
     * @notice Undelegates the staking operation from the current operator.
     * @dev It retrieves the current operator by calling `delegatedTo` on the DelegationManager for event logging.
     *      Calls the function on the version v0.2 of the Eigenlayer interface
     */
    function undelegate() public override onlyAdmin {
        
        IDelegationManagerV02 delegationManager = IDelegationManagerV02(address(stakingNodesManager.delegationManager()));
        address operator = delegationManager.delegatedTo(address(this));
        delegationManager.undelegate(address(this));

        emit Undelegated(operator);
    }

    /**
     * @notice Validates the withdrawal credentials of validators through the Eigenlayer protocol.
     * @dev Upon successful validation, Eigenlayer issues shares to the StakingNode, equivalent to the staked ETH amount.
     * @dev Calls the function on the version v0.2 of the Eigenlayer interface.
     */
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofsV02.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    ) external onlyAdmin {

        if (validatorIndices.length != withdrawalCredentialProofs.length) {
            revert MismatchedValidatorIndexAndProofsLengths(validatorIndices.length, withdrawalCredentialProofs.length);
        }
        if (withdrawalCredentialProofs.length != validatorFields.length) {
            revert MismatchedProofsAndValidatorFieldsLengths(withdrawalCredentialProofs.length, validatorFields.length);
        }

        IEigenPodV02(address(eigenPod)).verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            withdrawalCredentialProofs,
            validatorFields
        );
    }
}
