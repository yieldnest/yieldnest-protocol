// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import { EigenPod } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";

contract MockEigenPod is EigenPod {
    constructor(
        IETHPOSDeposit _ethPOS,
        IDelayedWithdrawalRouter _delayedWithdrawalRouter,
        IEigenPodManager _eigenPodManager,
        uint64 _MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR,
        uint64 _GENESIS_TIME
    ) EigenPod(_ethPOS, _delayedWithdrawalRouter, _eigenPodManager, _MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR, _GENESIS_TIME) {}

    function setPodOwner(address newOwner) external {
        require(newOwner != address(0), "MockEigenPod: New owner is the zero address");
        podOwner = newOwner;
    }

    function setValidatorInfo(
        bytes32 validatorPubkeyHash,
        ValidatorInfo memory validatorInfo
    ) external {
        _validatorPubkeyHashToInfo[validatorPubkeyHash] = validatorInfo;
    }
}
