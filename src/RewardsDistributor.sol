// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./RewardsReceiver.sol";
import {IynETH} from "./interfaces/IynETH.sol";


interface RewardsDistributorEvents {
    event FeesCollected(uint256 amount);
    event FeeReceiverSet(address ewReceiver);
}


contract RewardsDistributor is Initializable, AccessControlUpgradeable, RewardsDistributorEvents {

    error InvalidConfiguration();
    error NotOracle();
    error Paused();
    error ZeroAddress();

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    IynETH ynETH;

    /// @notice The contract receiving execution layer rewards, both tips and MEV rewards.
    RewardsReceiver public executionLayerReceiver;

    /// @notice The address receiving protocol fees.
    address payable public feesReceiver;

    /// @notice The protocol fees in basis points (1/10000).
    uint16 public feesBasisPoints;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        RewardsReceiver executionLayerReceiver;
        address payable feesReceiver;
        IynETH ynETH;
    }

    function initialize(Init memory init) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        executionLayerReceiver = init.executionLayerReceiver;
        feesReceiver = init.feesReceiver;
        ynETH = init.ynETH;
        // Default fees are 10%
        feesBasisPoints = 1_000;
    }

    function processRewards()
        external
        assertBalanceUnchanged
    {

        uint256 totalRewards = 0;

        uint256 elRewards = address(executionLayerReceiver).balance;
        totalRewards += elRewards;
        
        // Calculate protocol fees.
        uint256 fees = Math.mulDiv(feesBasisPoints, totalRewards, _BASIS_POINTS_DENOMINATOR);

        // Aggregate returns in this contract
        address payable self = payable(address(this));
        executionLayerReceiver.transferETH(self, elRewards);

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

    receive() external payable {}

    /// @notice Ensures that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address addr) {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

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
}
