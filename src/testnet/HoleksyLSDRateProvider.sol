// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IstETH} from "src/external/lido/IstETH.sol";
import {IrETH} from "src/external/rocketpool/IrETH.sol";
import {ImETHStaking} from "src/external/mantle/ImETHStaking.sol";


struct StaderExchangeRate {
    uint256 block_number;
    uint256 eth_balance;
    uint256 ethx_supply;
}

interface StaderOracle {
    function getExchangeRate() external view returns (StaderExchangeRate memory);
}

contract HoleskyLSDRateProvider {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(address asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------


    uint256 public constant UNIT = 1e18;
    address public constant FRAX_ASSET = 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3; // sfrxETH
    address public constant LIDO_ASSET = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D; // wstETH
    address public constant RETH_ASSET = 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1; // RETH

    /** WOETH is a mock deployed by YieldNest */
    address public constant WOETH_ASSET = 0xbaAcDcC565006b6429F57bC0f436dFAf14A526b1;
    address public constant METH_ASSET = 0xe3C063B1BEe9de02eb28352b55D49D85514C67FF;
    address public constant METH_STAKING_CONTRACT = 0xbe16244EAe9837219147384c8A7560BA14946262;
    address public constant LIDO_UDERLYING = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034; // stETH

    /// STADER
    address public constant STADER_ORACLE = 0x90ED1c6563e99Ea284F7940b1b443CE0BC4fC3e4;
    address public constant STADER_ASSET = 0xB4F5fc289a778B80392b86fa70A7111E5bE0F859; //ETHX

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
     */
    function rate(address _asset) external view returns (uint256) {

        /*
            This contract uses the rate as provided the protocol that controls the asset.
            This approach avoids issues with sourcing market prices that would cause asset value
            fluctuation that depends on market price fluctuation
            Known risks that require mitigation:
            In case one of the LSDs depegs from its ETH price, users can still deposit to ynEigen, 
            and receive the same amount of shares as though the underlying asset has not depegged yet,
            as the protocols below will report the same LSD/ETH price.
        */

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
        if (_asset == METH_ASSET) {
            return ImETHStaking(METH_STAKING_CONTRACT).mETHToETH(UNIT);
        }

        if (_asset == STADER_ASSET) {
            StaderExchangeRate memory res = StaderOracle(STADER_ORACLE).getExchangeRate();
            return (res.eth_balance * UNIT) / res.ethx_supply;
        }
        
        revert UnsupportedAsset(_asset);
    }
}
