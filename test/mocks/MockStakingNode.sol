// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {StakingNode} from "src/StakingNode.sol";

contract MockStakingNode is StakingNode {
    function setEigenPod(IEigenPod _eigenPod) public {
        if (address(_eigenPod) == address(0)) revert ZeroAddress();
        eigenPod = _eigenPod;
        emit EigenPodCreated(address(this), address(_eigenPod));
    }
}
