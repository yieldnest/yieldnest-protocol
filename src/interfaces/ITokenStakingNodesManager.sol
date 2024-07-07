pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";

interface ITokenStakingNodesManager {

    function createLSDStakingNode() external returns (ITokenStakingNode);
    function registerLSDStakingNodeImplementationContract(address _implementationContract) external;
    function upgradeLSDStakingNodeImplementation(address _implementationContract) external;
    function setMaxNodeCount(uint256 _maxNodeCount) external;
    function hasLSDRestakingManagerRole(address account) external view returns (bool);

    function delegationManager() external view returns (IDelegationManager);
    function strategyManager() external view returns (IStrategyManager);
    function upgradeableBeacon() external view returns (UpgradeableBeacon);
    function strategies(IERC20 asset) external view returns (IStrategy);


    function getAllNodes() external view returns (ITokenStakingNode[] memory);
    function nodesLength() external view returns (uint256);
    function hasEigenStrategyManagerRole(address) external view returns (bool);

}
