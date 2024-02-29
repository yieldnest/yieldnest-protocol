// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Third-party imports: OZ
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal deps.
import {RewardsReceiver} from "./RewardsReceiver.sol";

//@audit TODO auto-generate interfaces files: https://ethereum.stackexchange.com/a/155661

/// @title RewardsDistributor
/// @notice TODO
contract RewardsDistributor is 
    Initializable, 
    AccessControlUpgradeable, 
    RewardsDistributorEvents 
{
    /******************************\
    |                              |
    |             Errors           |
    |                              |
    \******************************/

    error InvalidConfiguration();
    error NotOracle();
    error Paused();
    error ZeroAddress();
    error FeeTransferFailed();
    error RewardsDistributor_FeesReceiverAlreadyCurrent();

    /******************************\
    |                              |
    |             Events           |
    |                              |
    \******************************/


    /******************************\
    |                              |
    |            Structs           |
    |                              |
    \******************************/

    /// @notice Configuration for contract initialization.
    /// @dev Only used in memory (i.e. layout doesn't matter!)
    /// @param admin The initial admin of this contract.
    /// @param rewardsReceiver The RewardsReceiver contract.
    /// @param feesReceiver The address receiving the fees.
    /// @param ynETH The ynETH contract.
    struct Init {
        address admin;
        address rewardsReceiver;
        address payable feesReceiver;
        address payable ynETH;
    }

    /******************************\
    |                              |
    |           Constants          |
    |                              |
    \******************************/

    /// @notice 100%
    uint private constant BASIS_POINTS_DENOMINATOR = 100_00;

    /// @notice 10%
    uint private constant DEFAULT_FEES_BASIS_POINTS = 10_00;

    /******************************\
    |                              |
    |       Storage variables      |
    |                              |
    \******************************/

    /// @notice The ynETH contract.
    address public ynETH;

    /// @notice The contract receiving execution layer rewards, both tips and MEV rewards.
    IRewardsReceiver public rewardsReceiver;

    /// @notice The address receiving protocol fees.
    address payable public feesReceiver;

    /// @notice The protocol fees in basis points (1/100_00), 1% == 1_00.
    uint public feesBasisPoints;

    /******************************\
    |                              |
    |          Constructor         |
    |                              |
    \******************************/

    /// @notice The constructor.
    /// @dev calling _disableInitializers() to prevent the implementation from being initializable.
    constructor() {
       _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @param init The init params.
    function initialize(Init calldata _init) 
        public 
        notZeroAddress(init.admin)
        notZeroAddress(init.rewardsReceiver)
        notZeroAddress(init.feesReceiver)
        notZeroAddress(init.ynETH)
        initializer 
    {
        // Initialize all the parent contracts.
        __AccessControl_init();

        // Assign all the roles.
        _grantRole(DEFAULT_ADMIN_ROLE, _init.admin);

        // Store configuration values.
        feesBasisPoints = DEFAULT_FEES_BASIS_POINTS;

        // Store all of the addresses of interacting contracts.
        ynETH = _init.ynETH;
        rewardsReceiver = IRewardsReceiver(_init.rewardsReceiver);
        feesReceiver = _init.feesReceiver;

    }

    /******************************\
    |                              |
    |         Core functions       |
    |                              |
    \******************************/

    /// @notice Fetches rewards from the RewardsReceiver contract, sends the fee
    ///         part of that to the feesReceiver, and the remainder to the
    ///         ynETH contract.
    /// @param to The recipient of the ETH.
    /// @param amount The amount of ETH to transfer.
    function processRewards() 
        external 
        assertBalanceUnchanged 
    {        
        // First withdraw all rewards from the RewardsReceiver contract.
        uint rewards = address(rewardsReceiver).balance;
        rewardsReceiver.withdrawEth(address(this), rewards);
        
        // Then, calculate how much of those rewards are for the protocol fee.
        // totalRewards * (feesBasisPoints / BASIS_POINTS_DENOMINATOR)
        uint fee = Math.mulDiv(rewards, feesBasisPoints, BASIS_POINTS_DENOMINATOR);
        
        // Then, calculate the amount of rewards left over after subtracting the fee amount.
        uint netRewards = rewards - fee;

        // If there are net rewards left, transfer that amount to the ynETH contract.
        if (netRewards > 0) ynETH.call(netRewards)}("");

        // If there is a protocol fee, transfer it to the feeReceiver.
        if (fees > 0) {
            (bool success, ) = feesReceiver.call{value: fees}("");
            if (!success) {
                revert RewardsDistributor_FeeTransferFailed();
            }
            emit FeesCollected(fees);
        }
    }

    //@audit who calls this?
    /// @notice Receive ETH.
    receive() 
        external payable 
    {}

    /******************************\
    |                              |
    |    Configuration functions   |
    |                              |
    \******************************/

    /// @notice Sets the fees receiver wallet for the protocol.
    /// @param newReceiver The new fees receiver wallet.
    function setFeesReceiver(address payable _feesReceiver)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        notZeroAddress(_feesReceiver)
    {
        if (_feesReceiver == feesReceiver) {
            revert RewardsDistributor_FeesReceiverAlreadyCurrent();
        }
        emit FeeReceiverUpdated(feesReceiver, _feesReceiver);
        feesReceiver = _feesReceiver;
    }

    /******************************\
    |                              |
    |           Modifiers          |
    |                              |
    \******************************/

    /// @notice Ensure that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert RewardsDistributor_ZeroAddress();
        }
        _;
    }

    /// @notice Ensures that the ETH balance of this contract did not change.
    modifier assertBalanceUnchanged() {
        uint before = address(this).balance;
        _;
        assert(address(this).balance == before);
    }
}
