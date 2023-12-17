
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IOracle {

    struct Answer {
        uint cumulativeProcessedDepositAmount;
        uint currentTotalValidatorBalance;
    }

    function latestAnswer() external view returns (Answer memory);
}