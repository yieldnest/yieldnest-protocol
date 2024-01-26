pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IDepositPool.sol";
import "./interfaces/IStakingNodesManager.sol";

contract Oracle is Initializable, AccessControlUpgradeable, IOracle {


    event OracleReporterSet(address newReporter);

    error CumulativeProcessedDepositAmountDecreased(uint previousReportIndex, uint  cumulativeProcessedDepositAmount);
    error InvalidUpdateStartBlock(uint previousReportIndex, uint updateStartBlock);
    error UnauthorizedOracleReporter(address caller, address oracleReporter);
    error ZeroAddress();

    IStakingNodesManager stakingNodesManager;
    Report[] public reports;
    address public oracleReporter;

    struct Init {
        IStakingNodesManager stakingNodesManager;
        address admin;
        address oracleReporter;
    }

    modifier onlyReporter {
        if (msg.sender != oracleReporter) {
            revert UnauthorizedOracleReporter(msg.sender, oracleReporter);
        }
         _;
    }

    modifier notZeroAddress(address addr) {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(Init memory init) public initializer {
        stakingNodesManager = init.stakingNodesManager;
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        oracleReporter = init.oracleReporter;
    }


   function submitReport(Report calldata newReport) external onlyReporter {

        /*
        Fully implement oracle record processing and validation.
        */

        validateReport(newReport, reports.length - 1);

        reports.push(newReport);
    }

    function validateReport(Report memory newReport, uint previousReportIndex) public view {
        Report memory previousReport = reports[previousReportIndex];

        if (newReport.cumulativeProcessedDepositAmount < previousReport.cumulativeProcessedDepositAmount) {
            revert CumulativeProcessedDepositAmountDecreased(previousReportIndex, newReport.cumulativeProcessedDepositAmount);
        }

        if (newReport.updateStartBlock != previousReport.updateEndBlock + 1) {
            revert InvalidUpdateStartBlock(previousReportIndex, newReport.updateStartBlock);
        }
    }

    function latestReport() public view returns (Report memory report) {
        return reports[reports.length];
    }


    function setOracleReporter(address newReporter) external onlyRole(DEFAULT_ADMIN_ROLE) notZeroAddress(newReporter) {
        oracleReporter = newReporter;
        emit OracleReporterSet(newReporter);
    }
}

