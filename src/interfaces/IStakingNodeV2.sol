import "./IStakingNode.sol";

import {BeaconChainProofs as BeaconChainProofsv021 } from "../external/eigenlayer/v0.2.1/BeaconChainProofs.sol";


interface IStakingNodeV2 is IStakingNode {

    function verifyWithdrawalCredentials(
        uint256 oracleTimestamp,
        BeaconChainProofsv021.StateRootProof memory stateRootProof,
        uint40[] memory validatorIndexes,
        bytes[] memory validatorFieldsProofs,
        bytes32[][] memory validatorFields
    ) external;
}
