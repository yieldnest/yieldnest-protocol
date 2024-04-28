// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { IEigenPod } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import { IETHPOSDeposit } from "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import { IStrategyManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import { ISlasher } from "lib/eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import { IDelegationManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import { EigenPodManager } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
//import { IBeacon } from "lib/eigenlayer-contracts/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import { IBeacon } from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

contract MockEigenPodManager is EigenPodManager {

    constructor(EigenPodManager _eigenPodManagerInstance)
        EigenPodManager(
            _eigenPodManagerInstance.ethPOS(),
            _eigenPodManagerInstance.eigenPodBeacon(),
            _eigenPodManagerInstance.strategyManager(),
            _eigenPodManagerInstance.slasher(),
            _eigenPodManagerInstance.delegationManager()
        ) {}
    // Function to manually set the hasPod status for a given owner in the mock
    function setHasPod(address podOwner, IEigenPod pod) external {
        ownerToPod[podOwner] = pod;
    }
}
