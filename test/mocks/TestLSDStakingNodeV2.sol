// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "src/LSDStakingNode.sol";

contract TestLSDStakingNodeV2 is LSDStakingNode {

    uint public valueToBeInitialized;

    struct ReInit { 
        uint valueToBeInitialized;
    }

    function initializeV2(ReInit memory reInit) public reinitializer(2) {
        valueToBeInitialized = reInit.valueToBeInitialized;
    }

    function redundantFunction() public pure returns (uint256) {
        return 1234567;
    }
}
