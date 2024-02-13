import {IDelegationManager as IDelegationManagerM2 } from "./interfaces/eigenlayer/IDelegationManager.sol";
import {IEigenPod as IEigenPodM2 } from "./interfaces/eigenlayer/IEigenPod.sol";
import {ISignatureUtils} from "./interfaces/eigenlayer/ISignatureUtils.sol";
import { BeaconChainProofs as BeaconChainProofsM2 } from "./external/eigenlayer/BeaconChainProofs.sol";


import "./StakingNode.sol";


contract StakingNodeM2 is StakingNode {
    // Additional functionality or overrides can be implemented here.

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

            totalETHNotRestaked -= (validatorBalanceGwei * 1e9);
        }
    }

    function verifyWithdrawalCredentials(
        uint64[] calldata oracleBlockNumber,
        uint40[] calldata validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] calldata proofs,
        bytes32[][] calldata validatorFields
    ) external override {
        revert("StakingNode: Sunset functionality");
    }


}
