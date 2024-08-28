// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract HoleskyLSDRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------


    uint256 public constant UNIT = 1e18;

    // YnUSD and YnSUSD addresses on Holesky
    address public constant YNUSD_ASSET = 0x40a87fF2d853290157bcB3E3494e53784524651a; // Replace with actual address
    address public constant YNSUSD_ASSET = 0x6bd62ECCddd48a1d42ED04D9b19592f07cCC5794; // Replace with actual address

    /**
     * @dev Returns the rate of the specified asset.
     * @param _asset The address of the asset for which to get the rate.
     * @return The rate of the specified asset in terms of its underlying value.
     * @notice This function now also supports YnUSD and YnSUSD on Holesky.
     */
    function rate(address _asset) external view returns (uint256) {

        if (_asset == YNUSD_ASSET) {
            return UNIT; // YnUSD has a 1:1 ratio with USD
        }
        if (_asset == YNSUSD_ASSET) {
            return IERC4626(YNSUSD_ASSET).totalAssets() * UNIT / IERC20(YNSUSD_ASSET).totalSupply();
        }
        
        revert UnsupportedAsset(_asset);
    }
}

