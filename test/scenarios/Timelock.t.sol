// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import "./ScenarioBaseTest.sol";

contract TimelockTest is ScenarioBaseTest {

    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    uint256 public constant DELAY = 3 days;

    address[] public proxyContracts;

    TimelockController public timelock;

    // ============================================================================================
    // Setup
    // ============================================================================================

    function setUp() public override {
        ScenarioBaseTest.setUp();

        proxyContracts = [
            address(yneth),
            address(stakingNodesManager),
            address(rewardsDistributor),
            address(executionLayerReceiver),
            address(consensusLayerReceiver)
        ];

        address[] memory _proposers = new address[](1);
        _proposers[0] = actors.eoa.DEFAULT_SIGNER;
        address[] memory _executors = new address[](1);
        _executors[0] = actors.eoa.DEFAULT_SIGNER;
        timelock = new TimelockController(
            DELAY,
            _proposers,
            _executors,
            address(0) // no admin
        );
    }

    // ============================================================================================
    // Tests
    // ============================================================================================

    function testScheduleAndExecuteUpgrade() public {
        _updateProxyAdminOwnersToTimelock();

        // operation data
        address _target = getTransparentUpgradeableProxyAdminAddress(address(yneth)); // proxy admin
        address _implementation = getTransparentUpgradeableProxyImplementationAddress(address(yneth)); // implementation (not changed)
        uint256 _value = 0;
        bytes memory _data = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            address(yneth), // proxy
            _implementation, // implementation
            "" // no data
        );
        bytes32 _predecessor = bytes32(0);
        bytes32 _salt = bytes32(0);
        uint256 _delay = 3 days;

        vm.startPrank(actors.eoa.DEFAULT_SIGNER);

        // schedule
        timelock.schedule(
            _target,
            _value,
            _data,
            _predecessor,
            _salt,
            _delay
        );

        // skip delay duration
        skip(DELAY);

        vm.expectEmit(address(yneth));
        emit Upgraded(_implementation);

        // execute
        timelock.execute(
            _target,
            _value,
            _data,
            _predecessor,
            _salt
        );

        vm.stopPrank();
    }

    // @note: change the owner of the contract from the timelock to the default signer
    function testSwapTimelockOwnership() public {
        _updateProxyAdminOwnersToTimelock();

        // operation data
        address _newOwner = actors.eoa.DEFAULT_SIGNER;
        address _target = getTransparentUpgradeableProxyAdminAddress(address(yneth)); // proxy admin
        assertEq(Ownable(_target).owner(), address(timelock), "testSwapTimelockOwnership: E0"); // check current owner

        uint256 _value = 0;
        bytes memory _data = abi.encodeWithSignature(
            "transferOwnership(address)",
            _newOwner, // new owner
            "" // no data
        );
        bytes32 _predecessor = bytes32(0);
        bytes32 _salt = bytes32(0);
        uint256 _delay = 3 days;

        vm.startPrank(actors.eoa.DEFAULT_SIGNER);

        // schedule
        timelock.schedule(
            _target,
            _value,
            _data,
            _predecessor,
            _salt,
            _delay
        );

        // skip delay duration
        skip(DELAY);

        vm.expectEmit(address(_target));
        emit OwnershipTransferred(
            address(timelock), // oldOwner
            _newOwner // newOwner
        );

        // execute
        timelock.execute(
            _target,
            _value,
            _data,
            _predecessor,
            _salt
        );

        vm.stopPrank();

        assertEq(Ownable(_target).owner(), _newOwner, "testSwapTimelockOwnership: E1");
    }

    // ============================================================================================
    // Internal helpers
    // ============================================================================================

    function _updateProxyAdminOwnersToTimelock() internal {
        for (uint256 i = 0; i < proxyContracts.length; i++) {

            // get proxy admin
            Ownable _proxyAdmin = Ownable(getTransparentUpgradeableProxyAdminAddress(address(proxyContracts[i])));

            // transfer ownership to timelock
            vm.prank(_proxyAdmin.owner());
            _proxyAdmin.transferOwnership(address(timelock));
        }
    }
}