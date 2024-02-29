// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager,IStrategy} from "../external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {ILSDStakingNode} from "./ILSDStakingNode.sol";
import {ILSDStakingNode} from "./ILSDStakingNode.sol";


interface IynLSD {

    function deposit(
        IERC20 token,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function strategies(IERC20 asset) external view returns (IStrategy);

    function totalAssets() external view returns (uint);

    function convertToShares(IERC20 asset, uint amount) external view returns(uint shares);

    function createLSDStakingNode() external returns (ILSDStakingNode);

    function registerStakingNodeImplementationContract(address _implementationContract) external;

    function upgradeStakingNodeImplementation(address _implementationContract, bytes memory callData) external;

    function setMaxNodeCount(uint _maxNodeCount) external;

    function hasLSDRestakingManagerRole(address account) external returns (bool);

    function retrieveAsset(uint nodeId, IERC20 asset, uint256 amount) external;

    function strategyManager() external returns (IStrategyManager);
}