// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";

contract TestTokenStakingNodeV2 is TokenStakingNode {

    uint public valueToBeInitialized;

    struct ReInit { 
        uint valueToBeInitialized;
    }

    function initializeV3(ReInit memory reInit) public reinitializer(4) {
        valueToBeInitialized = reInit.valueToBeInitialized;
    }

    function redundantFunction() public pure returns (uint256) {
        return 1234567;
    }
}
