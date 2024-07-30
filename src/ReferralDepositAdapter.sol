// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { IynETH } from "src/interfaces/IynETH.sol";
import { IReferralDepositAdapter } from "src/interfaces/IReferralDepositAdapter.sol";
import { Initializable } from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

interface ReferralDepositAdapterEvents {
    event ReferralDepositProcessed(
        address indexed depositor, 
        address indexed receiver, 
        uint256 amount, 
        uint256 shares, 
        address indexed referrer, 
        uint256 timestamp,
        bool fromPublisher
    );
}


contract ReferralDepositAdapter is 
    IReferralDepositAdapter,
    ReferralDepositAdapterEvents,
    Initializable,
    AccessControlUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------
    
    error ZeroAddress();
    error ZeroETH();
    error NoDirectETHDeposit();
    error SelfReferral();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant REFERRAL_PUBLISHER_ROLE = keccak256("REFERRAL_PUBLISHER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynETH public ynETH;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    function initialize(Init memory init) public initializer {
        ynETH = init._ynETH;
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(REFERRAL_PUBLISHER_ROLE, init.referralPublisher);
    }

    constructor() {
         _disableInitializers();
    }

    /// @notice Proxies a deposit call to the ynETH with referral information.
    /// @notice IMPORTANT: The referred or referree is the receiver, NOT msg.sender
    /// @param receiver The address that will receive the ynETH shares. This is the referee address.
    /// @param referrer The address of the referrer.
    function depositWithReferral(address receiver, address referrer) external payable returns (uint256 shares) {
        if (msg.value == 0) {
            revert ZeroETH();
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == receiver) {
            revert SelfReferral();
        }

        shares = ynETH.depositETH{value: msg.value}(receiver);

        emit ReferralDepositProcessed(msg.sender, receiver, msg.value, shares, referrer, block.timestamp, false);
    }
    /// @notice Publishes multiple referral information using the existing event.
    /// @param referrals Array of ReferralInfo structs containing referral details.
    function publishReferrals(ReferralInfo[] calldata referrals) external  onlyRole(REFERRAL_PUBLISHER_ROLE)  {
        for (uint256 i = 0; i < referrals.length; i++) {
            emit ReferralDepositProcessed(
                referrals[i].depositor,
                referrals[i].referee,
                referrals[i].amountDeposited,
                referrals[i].shares,
                referrals[i].referrer,
                referrals[i].timestamp,
                true
            );
        }
    }

    receive() external payable {
        revert NoDirectETHDeposit();
    }
}
