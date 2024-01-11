pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract YieldNestStrategyManager is Initializable {
    mapping(address => bool) public nodeOperatorWhitelist;

    function addToWhitelist(address operator) public {
        nodeOperatorWhitelist[operator] = true;
    }

    function removeFromWhitelist(address operator) public {
        nodeOperatorWhitelist[operator] = false;
    }

    function isOperatorWhitelisted(address operator) public view returns (bool) {
        return nodeOperatorWhitelist[operator];
    }


    function initialize() public initializer {

    }

}
