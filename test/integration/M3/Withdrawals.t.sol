// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract M3WithdrawalsTest is Base {

    // todo - mock the BEACON_ROOTS_ADDRESS and update it's address in the EL eigenpod contract
    function testVerifyWithdrawalCredentials() public {
        if (block.chainid != 17000) return;

        // /**
        // * @dev Validates the withdrawal credentials for a withdrawal.
        // * This activates the staked funds within EigenLayer as shares.
        // * verifyWithdrawalCredentials MUST be called for all validators BEFORE they
        // * are exited from the beacon chain to keep the getETHBalance return value consistent.
        // * If a validator is exited without this call, TVL is double counted for its principal.
        // * @param beaconTimestamp The timestamp of the oracle that signed the block.
        // * @param stateRootProof The state root proof.
        // * @param validatorIndices The indices of the validators.
        // * @param validatorFieldsProofs The validator fields proofs.
        // * @param validatorFields The validator fields.
        // */
        // function verifyWithdrawalCredentials(
        //     uint64 beaconTimestamp,
        //     BeaconChainProofs.StateRootProof calldata stateRootProof,
        //     uint40[] calldata validatorIndices,
        //     bytes[] calldata validatorFieldsProofs,
        //     bytes32[][] calldata validatorFields
        // ) external onlyOperator {

        // -------------
        
        //         VerifyWithdrawalCredentialsCallParams memory params
        //             = setupVerifyWithdrawalCredentialsForProofFileForForeignValidator("test/data/ValidatorFieldsProof_1293592_8746783.json");

        //         uint64 oracleTimestamp = params.oracleTimestamp;
        //         IStakingNode stakingNodeInstance = params.stakingNodeInstance;
        //         ValidatorProofs memory validatorProofs = params.validatorProofs;

        //         uint256 stakingNodeETHBalanceBeforeVerification = stakingNodeInstance.getETHBalance();
        //         uint256 ynETHTotalAssetsBeforeVerification = yneth.totalAssets();

        //         vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        //         stakingNodeInstance.verifyWithdrawalCredentials(
        //             oracleTimestamp,
        //             validatorProofs.stateRootProof,
        //             validatorProofs.validatorIndices,
        //             validatorProofs.withdrawalCredentialProofs,
        //             validatorProofs.validatorFields
        //         );
    }

    // function testStartCheckpoint
    // function testVerifyCheckpointProofs
    // function todo - start withdrawal flow using `testVerifyCheckpointProofs`
}