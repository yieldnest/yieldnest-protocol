// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager,IStrategy} from "../external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "src/external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IynLSD {

    function deposit(
        IERC20 token,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function upgradeableBeacon() external view returns (UpgradeableBeacon);

    function strategies(IERC20 asset) external view returns (IStrategy);

    function totalAssets() external view returns (uint);

    function convertToShares(IERC20 asset, uint amount) external view returns(uint shares);

    function createLSDStakingNode() external returns (ILSDStakingNode);

    function registerLSDStakingNodeImplementationContract(address _implementationContract) external;

    function upgradeLSDStakingNodeImplementation(address _implementationContract) external;

    function setMaxNodeCount(uint _maxNodeCount) external;

    function hasLSDRestakingManagerRole(address account) external returns (bool);

    function retrieveAsset(uint nodeId, IERC20 asset, uint256 amount) external;

    function strategyManager() external returns (IStrategyManager);

    function delegationManager() external returns (IDelegationManager);
    
}