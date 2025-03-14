// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynLSDeScenarioBaseTest} from "../ynLSDeScenarioBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/src/contracts/interfaces/IPermissionController.sol";
import {IPauserRegistry} from "@eigenlayer/src/contracts/interfaces/IPauserRegistry.sol";
import {IETHPOSDeposit} from "@eigenlayer/src/contracts/interfaces/IETHPOSDeposit.sol";
// import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {IBeacon} from "@openzeppelin-v4.9.0/contracts/proxy/beacon/IBeacon.sol";


import {AllocationManager} from "@eigenlayer/src/contracts/core/AllocationManager.sol";
import {DelegationManager} from "@eigenlayer/src/contracts/core/DelegationManager.sol";
import {EigenPodManager} from "@eigenlayer/src/contracts/pods/EigenPodManager.sol";

contract PreUpgradeynEIGEN is ynLSDeScenarioBaseTest {

    IAllocationManager public allocationManager;

    address private user1;

    IPauserRegistry public pauserRegistry = IPauserRegistry(0x0c431C66F4dE941d089625E5B423D00707977060);
    IETHPOSDeposit public ethposDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    IBeacon public eigenPodBeacon = IBeacon(0x5a2a4F2F3C18f09179B6703e63D9eDD165909073);

    function setUp() public virtual override {
        super.setUp();

        user1 = makeAddr("user1");
        deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user1, give: 1000 ether});
    }

    // forge test --fork-url $MAINNET_RPC --match-contract PreUpgradeynEIGEN -vvvv --fork-block-number 22046726
    function testDepositBeforeELUpgradeAndBeforeynEigenUpgrade() public {}

    function testDepositAfterELUpgradeAndBeforeynEigenUpgrade() public {
        vm.startPrank(user1);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(yneigen), type(uint256).max);

        // upgrade ynEIGEN before deposit
        allocationManager =
            new AllocationManager(delegationManager, pauserRegistry, IPermissionController(address(2)), 1, 1);

        DelegationManager newDelegationManager = new DelegationManager(
            strategyManager, eigenPodManager, allocationManager, pauserRegistry, IPermissionController(address(2)), 1
        );
        vm.etch(address(delegationManager), address(newDelegationManager).code);

        EigenPodManager newEigenPodManager =
            new EigenPodManager(ethposDeposit, eigenPodBeacon, delegationManager, pauserRegistry);
        vm.etch(address(eigenPodManager), address(newEigenPodManager).code);

        yneigen.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), 1 ether, user1);

        vm.stopPrank();
    }

}
