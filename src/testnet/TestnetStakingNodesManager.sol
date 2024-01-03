// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.0;

import "../StakingNodesManager.sol";

contract TestnetStakingNodesManager is StakingNodesManager {
    // Function to set the delegationManager
    function setDelegationManager(IDelegationManager _delegationManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        delegationManager = _delegationManager;
    }
}

