// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";

import "./ynLSDeWithdrawals.t.sol";

contract ynLSDeDepositAdapterTest is ynLSDeWithdrawalsTest {

    TestAssetUtils public testAssetUtils;

    function setUp() public override {
        super.setUp();

        // upgrade deposit adapter
        {
            _upgradeContract(
                address(ynEigenDepositAdapter_),
                address(new ynEigenDepositAdapter()),
                abi.encodeWithSignature("initializeV2(address)", address(wrapper))
            );
        }

        // deploy testAssetUtils
        {
            testAssetUtils = new TestAssetUtils();
        }
    }

    // function testDepositSTETH(uint256 _amount) public {
    //     vm.assume(_amount > 0 && _amount <= 10 ether);

    //     testAssetUtils.get_stETH(user, _amount);

    //     vm.startPrank(user);
    //     IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(address(ynEigenDepositAdapter_), _amount);
    //     uint256 _ynOut = ynEigenDepositAdapter_.deposit(IERC20(chainAddresses.lsd.STETH_ADDRESS), _amount, user);
    //     vm.stopPrank();

    //     assertEq(IERC20(yneigen).balanceOf(user), _ynOut, "testDepositSTETH");
    // }

    function testDepositOETH(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= 10 ether);

        testAssetUtils.get_OETH(user, _amount);

        vm.startPrank(user);
        IERC20(chainAddresses.lsd.OETH_ADDRESS).approve(address(ynEigenDepositAdapter_), _amount);
        uint256 _ynOut = ynEigenDepositAdapter_.deposit(IERC20(chainAddresses.lsd.OETH_ADDRESS), _amount, user);
        vm.stopPrank();

        assertEq(IERC20(yneigen).balanceOf(user), _ynOut, "testDepositOETH");
    }
}