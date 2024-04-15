// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {IynETH} from "src/interfaces/IynETH.sol";


interface RewardsDistributorEvents {
    event RewardsProcessed(uint256 totalRewards, uint256 elRewards, uint256 clRewards, uint256 netRewards, uint256 fees);
    event FeeReceiverSet(address ewReceiver);
    event FeesBasisPointsSet(uint256 feeBasisPoints);
}

contract RewardsDistributor is Initializable, AccessControlUpgradeable, RewardsDistributorEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error Paused();
    error ZeroAddress();
    error FeeSendFailed();
    error InvalidBasisPoints();

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynETH public ynETH;

    /// @notice The contract receiving execution layer rewards, both tips and MEV rewards.
    RewardsReceiver public executionLayerReceiver;
    /// @notice The contract receiving consensus layer rewards.
    RewardsReceiver public consensusLayerReceiver;

    /// @notice The address receiving protocol fees.
    address payable public feesReceiver;

    /// @notice The protocol fees in basis points (1/10000).
    uint16 public feesBasisPoints;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        RewardsReceiver executionLayerReceiver;
        RewardsReceiver consensusLayerReceiver;
        address payable feesReceiver;
        IynETH ynETH;
    }

    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(address(init.executionLayerReceiver))
        notZeroAddress(address(init.consensusLayerReceiver))
        notZeroAddress(address(init.feesReceiver))
        notZeroAddress(address(init.ynETH))
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        executionLayerReceiver = init.executionLayerReceiver;
        consensusLayerReceiver = init.consensusLayerReceiver;
        feesReceiver = init.feesReceiver;
        ynETH = init.ynETH;
        // Default fees are 10%
        feesBasisPoints = 1_000;
    }

    receive() external payable {}

    //--------------------------------------------------------------------------------------
    //----------------------------------  REWARDS PROCESSING  ------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Processes rewards by aggregating them, calculating protocol fees, and distributing net rewards and fees.
     * This function aggregates rewards from the execution layer and consensus layer receivers, calculates the protocol fees,
     * transfers the aggregated rewards into this contract, sends the net rewards (after fees) to the ynETH contract, and
     * transfers the calculated fees to the fees receiver wallet. It ensures the contract's balance remains unchanged after execution.
     */
    function processRewards()
        external
        assertBalanceUnchanged
    {

        uint256 totalRewards = 0;

        uint256 elRewards = address(executionLayerReceiver).balance;
        uint256 clRewards = address(consensusLayerReceiver).balance;
        totalRewards += elRewards + clRewards;
        
        // Calculate protocol fees.
        uint256 fees = Math.mulDiv(feesBasisPoints, totalRewards, _BASIS_POINTS_DENOMINATOR);

        // Aggregate returns in this contract
        address payable self = payable(address(this));
        executionLayerReceiver.transferETH(self, elRewards);
        consensusLayerReceiver.transferETH(self, clRewards);

        uint256 netRewards = totalRewards - fees;
        if (netRewards > 0) {
            ynETH.receiveRewards{value: netRewards}();
        }

        // Send protocol fees (if they exist) to the fee receiver wallet.
        if (fees > 0) {
            (bool success, ) = feesReceiver.call{value: fees}("");
            if (!success) {
                revert FeeSendFailed();
            }
        }

        emit RewardsProcessed(totalRewards, elRewards, clRewards, netRewards, fees);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  SETTERS  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Sets the fees receiver wallet for the protocol.
    /// @param newReceiver The new fees receiver wallet.
    function setFeesReceiver(address payable newReceiver)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        notZeroAddress(newReceiver)
    {
        feesReceiver = newReceiver;
        emit FeeReceiverSet(newReceiver);
    }

    /// @notice Sets the fees basis points for the protocol.
    /// @param newFeesBasisPoints The new fees basis points.
    function setFeesBasisPoints(uint16 newFeesBasisPoints)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newFeesBasisPoints > _BASIS_POINTS_DENOMINATOR) revert InvalidBasisPoints();
        feesBasisPoints = newFeesBasisPoints;
        emit FeesBasisPointsSet(newFeesBasisPoints);
    }

    modifier assertBalanceUnchanged() {
        uint256 before = address(this).balance;
        _;
        assert(address(this).balance == before);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
