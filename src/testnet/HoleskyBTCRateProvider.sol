// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract HoleskyBTCRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant UNIT = 1e18;
    address constant public YNBTC_ASSET = 0x810615698eeAEE37efA98F821411aACe4e0d14e5;
    address constant public YNSBTC_ASSET = 0xf1BD6f0da70926d0d4c9Ed76ef4DBF6963972a13;

    //--------------------------------------------------------------------------------------
    //----------------------------------  FUNCTIONS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Returns the rate of the specified asset.
     * @param _asset The address of the asset for which to get the rate.
     * @return The rate of the specified asset in terms of its underlying value.
     * @notice This function handles YnBTC and ynSBTC assets and their respective rates.
     *         It reverts if the asset is not supported.
     *         The rates are sourced from each asset's specific redemption rate provider. 
     */
    function rate(address _asset) external view returns (uint256) {

        if (_asset == YNBTC_ASSET) {
            return UNIT; // YnUSD has a 1:1 ratio with USD
        }
        if (_asset == YNSBTC_ASSET) {
            return IERC4626(YNSBTC_ASSET).totalAssets() * UNIT / IERC20(YNSBTC_ASSET).totalSupply();
        }
        
        revert UnsupportedAsset(_asset);
    }
}
