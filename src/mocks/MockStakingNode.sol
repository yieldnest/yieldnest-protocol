pragma solidity ^0.8.0;

import "../StakingNode.sol";

contract MockStakingNode is StakingNode {
    function redundantFunction() public pure returns (uint256) {
        return 1234567;
    }
}
