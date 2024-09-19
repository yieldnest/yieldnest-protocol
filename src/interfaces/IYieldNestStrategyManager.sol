// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";

interface IRedemptionAssetsVaultExt is IRedemptionAssetsVault {
    function deposit(uint256 amount, address asset) external;
    function balances(address asset) external view returns (uint256 amount);
}

interface IYieldNestStrategyManager {

    struct WithdrawalAction {
        uint256 nodeId;
        uint256 amountToReinvest;
        uint256 amountToQueue;
        address asset;
    }

    function getStakedAssetsBalances(
        IERC20[] calldata assets
    ) external view returns (uint256[] memory stakedBalances);

    function getStakedAssetBalance(IERC20 asset) external view returns (uint256 stakedBalance);

    function supportsAsset(IERC20 asset) external view returns (bool);

    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);

    function processPrincipalWithdrawals(WithdrawalAction[] calldata _actions) external;

    function redemptionAssetsVault() external view returns (IRedemptionAssetsVaultExt);
}