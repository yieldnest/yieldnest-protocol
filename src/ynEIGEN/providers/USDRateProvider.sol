// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract USDRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant UNIT = 1e18;
    address constant public SDAI_ASSET = 0x83F20F44975D03b1b09e64809B757c47f942BEeA; // sDAI
    address constant public SUSDE_ASSET = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // sUSDe
    address constant public SFRAX_ASSET = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32; // sFRAX

    //--------------------------------------------------------------------------------------
    //----------------------------------  FUNCTIONS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Returns the rate of the specified asset.
     * @param _asset The address of the asset for which to get the rate.
     * @return The rate of the specified asset in terms of its underlying value.
     * @notice This function handles multiple types of USD-pegged assets and their respective rates.
     *         It supports Maker's sDAI, Ethena's sUSDe, and Frax's sFRAX.
     *         It reverts if the asset is not supported.
     *         The rates are sourced from each protocol's specific redemption rate provider. 
     */
    function rate(address _asset) external view returns (uint256) {
        if (_asset == SDAI_ASSET || _asset == SUSDE_ASSET || _asset == SFRAX_ASSET) {
            return IERC4626(_asset).convertToAssets(UNIT);
        }
        revert UnsupportedAsset(_asset);
    }
}
