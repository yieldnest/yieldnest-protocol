// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "./StakingNodesManager.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

contract HoleskyStakingNodesManager is StakingNodesManager {

     function initializeV3(
        IRewardsCoordinator _rewardsCoordinator
    ) external override reinitializer(3) {
        if (address(_rewardsCoordinator) == address(0)) revert ZeroAddress();
        rewardsCoordinator = _rewardsCoordinator;
    }

}   