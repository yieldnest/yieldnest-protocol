// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { IynETH } from "src/interfaces/IynETH.sol";

interface IReferralDepositAdapter {

    struct ReferralInfo {
        address depositor;
        address referrer;
        address referee;
        uint256 amountDeposited;
        uint256 shares;
        uint256 timestamp;
    }


    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address referralPublisher;
        IynETH _ynETH;
    }

    function ynETH() external view returns (IynETH);

    function depositWithReferral(address receiver, address referrer) external payable returns (uint256 shares);

    /// @notice Publishes multiple referral information using the existing event.
    /// @param referrals Array of ReferralInfo structs containing referral details.
    function publishReferrals(ReferralInfo[] calldata referrals) external;
}

