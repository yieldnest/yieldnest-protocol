// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BTCRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant UNIT = 1e18;
    address constant public TBTC_ASSET = 0x18084fbA666a33d37592fA2633fD49a74DD93a88; // tBTC
    address constant public DLCBTC_ASSET = address(0); // dlcBTC, TODO: find

    //--------------------------------------------------------------------------------------
    //----------------------------------  FUNCTIONS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Returns the rate of the specified asset.
     * @param _asset The address of the asset for which to get the rate.
     * @return The rate of the specified asset in terms of its underlying value.
     * @notice This function handles multiple types of BTC-pegged assets and their respective rates.
     *         It supports Threshold's tBTC and DLC.Link's dlcBTC.
     *         It reverts if the asset is not supported.
     *         The rates are sourced from each protocol's specific redemption rate provider. 
     */
    function rate(address _asset) external view returns (uint256) {
        if (_asset == TBTC_ASSET) {
            return UNIT; // TODO: see how to improve
        }
        if (_asset == DLCBTC_ASSET) {
            revert("Unsupported yet");
        }
        revert UnsupportedAsset(_asset);
    }
}
