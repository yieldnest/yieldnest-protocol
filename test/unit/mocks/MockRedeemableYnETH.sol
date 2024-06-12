// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockRedeemableYnETH is IRedeemableAsset, ERC20Burnable {
    constructor() ERC20("Mock Redeemable Asset", "MRA") {
        _mint(msg.sender, 1000 * 10 ** uint(decimals())); // Minting some initial supply for testing
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
     * @param amount The amount of tokens to preview the redemption for.
     * @return The amount of underlying asset that would be redeemed.
     */
    function previewRedeem(uint256 amount) public view returns (uint256) {
        return amount; // Assuming 1:1 redemption for simplicity in mock
    }
}
