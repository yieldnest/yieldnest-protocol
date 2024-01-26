
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IOracle {

    struct Report {
        uint cumulativeProcessedDepositAmount;
        uint currentTotalValidatorBalance;
    }

    function latestReport() external view returns (Report memory);
}