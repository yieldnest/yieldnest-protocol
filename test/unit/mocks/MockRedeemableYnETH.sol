// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console.sol";


contract MockRedeemableYnETH is IRedeemableAsset, ERC20Burnable {

    uint256 public totalAssets; // ETH denominated

    constructor() ERC20("Mock Redeemable Asset", "MRA") {
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return 18;
    }

    function burn(uint256 amount) public override(IRedeemableAsset, ERC20Burnable) {
        super.burn(amount);
    }

    /**
     * @notice Provides a preview of the amount of underlying asset that would be redeemed for a given amount of tokens.
     * @param shares The amount of tokens to preview the redemption for.
     * @return The amount of underlying asset that would be redeemed.
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
       return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {

        uint256 supply = totalSupply();

        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this call is made before boostrap call, not totalAssets
        if (supply == 0) {
            return shares;
        }

        return Math.mulDiv(shares, totalAssets, supply, rounding);
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssets = _totalAssets;
    }
}
