pragma solidity ^0.8.0;

import "../../../src/StakingNode.sol";

contract MockStakingNode is StakingNode {

    uint public valueToBeInitialized;

    struct ReInit { 
        uint valueToBeInitialized;
    }

    function reinitialize(ReInit memory reInit) public reinitializer(2) {
        valueToBeInitialized = reInit.valueToBeInitialized;
    }

    function redundantFunction() public pure returns (uint256) {
        return 1234567;
    }
}
