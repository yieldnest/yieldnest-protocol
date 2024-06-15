// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager,IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IynLSD {

    function deposit(
        IERC20 token,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function totalAssets() external view returns (uint);

    function convertToShares(IERC20 asset, uint amount) external view returns(uint shares);
    
}