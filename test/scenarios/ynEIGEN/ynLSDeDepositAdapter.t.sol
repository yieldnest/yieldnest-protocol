// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";

import "./ynLSDeWithdrawals.t.sol";

contract ynLSDeDepositAdapterTest is ynLSDeScenarioBaseTest {

    TestAssetUtils public testAssetUtils;

    address public constant user = address(0x42069);

    uint256 public constant AMOUNT = 1 ether;

    function setUp() public override {
        super.setUp();

        // deploy testAssetUtils
        {
            testAssetUtils = new TestAssetUtils();
        }
    }

    function testDepositSTETH(uint256 _amount) public {
        vm.assume(_amount > 10_000 && _amount <= 10 ether);

        testAssetUtils.get_stETH(user, _amount);

        vm.startPrank(user);
        IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(address(ynEigenDepositAdapter_), _amount);
        uint256 _ynOut = ynEigenDepositAdapter_.deposit(IERC20(chainAddresses.lsd.STETH_ADDRESS), _amount, user);
        vm.stopPrank();

        assertEq(IERC20(yneigen).balanceOf(user), _ynOut, "testDepositSTETH");
    }

    function testDepositOETH(uint256 _amount) public skipOnHolesky {
        vm.assume(_amount > 10_000 && _amount <= 10 ether);

        testAssetUtils.get_OETH(user, _amount + 10);

        vm.startPrank(user);
        IERC20(chainAddresses.lsd.OETH_ADDRESS).approve(address(ynEigenDepositAdapter_), _amount);
        uint256 _ynOut = ynEigenDepositAdapter_.deposit(IERC20(chainAddresses.lsd.OETH_ADDRESS), _amount, user);
        vm.stopPrank();

        assertEq(IERC20(yneigen).balanceOf(user), _ynOut, "testDepositOETH");
    }
}