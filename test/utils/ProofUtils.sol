/// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ProofParsing} from "lib/eigenlayer-contracts/src/test/utils/ProofParsing.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import "forge-std/StdJson.sol";

contract ProofUtils is ProofParsing {

    constructor(string memory path) {
        //setJSON("lib/eigenlayer-contracts/src/test/test-data/fullWithdrawalProof_Latest.json");
        setJSON((path));
    }

    function _getStateRootProof() external returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(
            getBeaconStateRoot(), abi.encodePacked(ProofParsing.getStateRootProof())
        );
    }

    function convertBytes32ArrayToBytesArray(bytes32[] memory input) public pure returns (bytes[] memory) {
        bytes[] memory output = new bytes[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = abi.encodePacked(input[i]);
        }
        return output;
    }

    function _getValidatorFieldsProof() public returns(bytes[] memory) {
        bytes32[] memory validatorFieldsProof = new bytes32[](46);
        for (uint i = 0; i < 46; i++) {
            prefix = string.concat(".ValidatorProof[", string.concat(vm.toString(i), "]"));
            validatorFieldsProof[i] = (stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return convertBytes32ArrayToBytesArray(validatorFieldsProof);
    }
}