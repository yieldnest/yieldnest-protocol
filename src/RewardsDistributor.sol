// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {RewardsReceiver} from "./RewardsReceiver.sol";
import {IynETH} from "./interfaces/IynETH.sol";


interface RewardsDistributorEvents {
    event FeesCollected(uint256 amount);
    event FeeReceiverSet(address ewReceiver);
}


contract RewardsDistributor is Initializable, AccessControlUpgradeable, RewardsDistributorEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error InvalidConfiguration();
    error NotOracle();
    error Paused();
    error ZeroAddress();

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynETH ynETH;

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

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        RewardsReceiver executionLayerReceiver;
        RewardsReceiver consensusLayerReceiver;
        address payable feesReceiver;
        IynETH ynETH;
    }

    function initialize(Init memory init)
        public
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
            emit FeesCollected(fees);
            //Address.sendValue(feesReceiver, fees);
            (bool success, ) = feesReceiver.call{value: fees}("");
            require(success, "Failed to send fees");
        }
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
