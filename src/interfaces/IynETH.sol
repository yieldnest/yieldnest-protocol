// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";


interface IynETH is IERC20, IRedeemableAsset {
    function withdrawETH(uint256 ethAmount) external;
    function processWithdrawnETH() external payable;
    function receiveRewards() external payable;
    function pauseDeposits() external;
    function unpauseDeposits() external;
    
    /// @notice Allows depositing ETH into the contract in exchange for shares.
    /// @param receiver The address to receive the minted shares.
    /// @return shares The amount of shares minted for the deposited ETH.
    function depositETH(address receiver) external payable returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Returns the total amount of assets managed by the contract.
    /// @return The total amount of assets in wei.
    function totalAssets() external view returns (uint256);

    /// @notice Returns the address of the StakingNodesManager contract.
    /// @return The address of the StakingNodesManager contract.
    function stakingNodesManager() external view returns (IStakingNodesManager);

    /// @notice Simulates the effects of a deposit at the current block, given the amount of assets.
    /// @param assets The amount of assets to simulate depositing.
    /// @return shares The amount of shares that would be minted.
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
}
