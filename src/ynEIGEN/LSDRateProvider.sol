// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IstETH} from "src/external/lido/IstETH.sol";
import {IrETH} from "src/external/rocketpool/IrETH.sol";

contract LSDRateProvider is Initializable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant UNIT = 1e18;
    address constant FRAX_ASSET = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
    address constant LIDO_ASSET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH
    address constant RETH_ASSET = 0xae78736Cd615f374D3085123A210448E74Fc6393; // RETH
    address constant WOETH_ASSET = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;

    address constant LIDO_UDERLYING = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    function rate(address _asset) external view returns (uint256) {
        if (_asset == LIDO_ASSET) {
            return IstETH(LIDO_UDERLYING).getPooledEthByShares(UNIT);
        }
        if (_asset == FRAX_ASSET) {
            return IERC4626(FRAX_ASSET).totalAssets() * UNIT / IERC20(FRAX_ASSET).totalSupply();
        }
        if (_asset == WOETH_ASSET) {
            return IERC4626(WOETH_ASSET).previewRedeem(UNIT);
        }
        if (_asset == RETH_ASSET) {
            return IrETH(RETH_ASSET).getExchangeRate();
        }
        revert UnsupportedAsset(_asset);
    }
}
