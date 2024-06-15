pragma solidity ^0.8.24;

import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

interface ITokenStakingNodesManager {
    function getStakedAssetsBalances(
        IERC20[] calldata assets
     ) external view returns (uint256[] memory stakedBalances);

    function createLSDStakingNode() external returns (ILSDStakingNode);
    function registerLSDStakingNodeImplementationContract(address _implementationContract) external;
    function upgradeLSDStakingNodeImplementation(address _implementationContract) external;
    function setMaxNodeCount(uint256 _maxNodeCount) external;
    function retrieveAsset(uint256 nodeId, IERC20 asset, uint256 amount) external;
    function hasLSDRestakingManagerRole(address account) external view returns (bool);

    function delegationManager() external view returns (IDelegationManager);
    function strategyManager() external view returns (IStrategyManager);
    function upgradeableBeacon() external view returns (UpgradeableBeacon);
    function strategies(IERC20 asset) external view returns (IStrategy);
}
