// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IstETH} from "src/external/lido/IstETH.sol";
import {IrETH} from "src/external/rocketpool/IrETH.sol";
import {IswETH} from "src/external/swell/IswETH.sol";
import {ImETHStaking} from "src/external/mantle/ImETHStaking.sol";
import {IFrxEthWethDualOracle} from "src/external/frax/IFrxEthWethDualOracle.sol";
import {IsfrxETH} from "src/external/frax/IsfrxETH.sol";

contract LSDRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant UNIT = 1e18;
    address constant public FRAX_ASSET = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
    address constant public FRX_ETH_WETH_DUAL_ORACLE = 0x350a9841956D8B0212EAdF5E14a449CA85FAE1C0; // FrxEthWethDualOracle
    address constant public LIDO_ASSET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH
    address constant public RETH_ASSET = 0xae78736Cd615f374D3085123A210448E74Fc6393; // RETH
    address constant public WOETH_ASSET = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address constant public SWELL_ASSET = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant public METH_ASSET = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant public METH_STAKING_CONTRACT = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;

    address constant public LIDO_UDERLYING = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Returns the rate of the specified asset.
     * @param _asset The address of the asset for which to get the rate.
     * @return The rate of the specified asset in terms of its underlying value.
     * @notice This function handles multiple types of liquid staking derivatives (LSDs) and their respective rates.
     *         It supports Lido's stETH, Frax's sfrxETH, Rocket Pool's rETH, Swell's swETH, and Wrapped stETH.
     *         It reverts if the asset is not supported.
     *         The rates are sourced from each protocol's specific redemption rate provider. 
     */
    function rate(address _asset) external view returns (uint256) {

        if (_asset == LIDO_ASSET) {
            return IstETH(LIDO_UDERLYING).getPooledEthByShares(UNIT);
        }
        if (_asset == FRAX_ASSET) {
            /* 
            
            The deposit asset for sfrxETH is frxETH and not ETH. In order to account for any frxETH/ETH rate fluctuations,
            an frxETH/ETH oracle is used as provided by Frax.

            Documentation: https://docs.frax.finance/frax-oracle/advanced-concepts
            */
            uint256 frxETHPriceInETH = IFrxEthWethDualOracle(FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
            return IsfrxETH(FRAX_ASSET).pricePerShare() * frxETHPriceInETH / UNIT;
        }
        if (_asset == WOETH_ASSET) {
            return IERC4626(WOETH_ASSET).previewRedeem(UNIT);
        }
        if (_asset == RETH_ASSET) {
            return IrETH(RETH_ASSET).getExchangeRate();
        }
        if (_asset == METH_ASSET) {
            return ImETHStaking(METH_STAKING_CONTRACT).mETHToETH(UNIT);
        }
        if (_asset == SWELL_ASSET) {
            return IswETH(SWELL_ASSET).swETHToETHRate();
        }
        revert UnsupportedAsset(_asset);
    }
}
