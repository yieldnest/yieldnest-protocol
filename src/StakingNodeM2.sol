import {IDelegationManager as IDelegationManagerM2 } from "./interfaces/eigenlayer/IDelegationManager.sol";
import {ISignatureUtils} from "./interfaces/eigenlayer/ISignatureUtils.sol";

import "./StakingNode.sol";


contract StakingNodeM2 is StakingNode {
    // Additional functionality or overrides can be implemented here.


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

}
