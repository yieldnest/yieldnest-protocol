// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LSDWrapperModule} from "src/ynEIGEN/LSDWrapperModule.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";


contract LSDWrapperModuleTest is Test {
    LSDWrapperModule public wrapper;
    address public constant WSTETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address public constant WOETH = address(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);
    address public constant OETH = address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
    address public constant STETH = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    TestAssetUtils public testAssetUtils;

    function setUp() public {
        wrapper = new LSDWrapperModule(WSTETH, WOETH, OETH, STETH);
        testAssetUtils = new TestAssetUtils();
    }

    function testWrapStETH(
        // uint256 amount
    ) public {

        uint256 amount = 10 ether;
        //vm.assume(amount > 0 && amount <= 1000 ether);
        
        IERC20 stETH = IERC20(STETH);
        uint256 balance = testAssetUtils.get_stETH(address(this), amount);
        stETH.approve(WSTETH, balance);

        (bool success, bytes memory result) = address(wrapper).delegatecall(
            abi.encodeWithSignature("wrap(uint256,address)", balance, STETH)
        );
        require(success, "Delegatecall failed");
        (uint256 wrappedAmount, IERC20 wrappedToken) = abi.decode(result, (uint256, IERC20));

        assertEq(address(wrappedToken), WSTETH, "Wrapped token should be wstETH");
        assertGt(wrappedAmount, 0, "Wrapped amount should be greater than 0");
        assertEq(IERC20(WSTETH).balanceOf(address(this)), wrappedAmount, "Wrapped amount should be received");
    }

    function testUnwrapWstETH(
        // uint256 amount
    ) public {
        uint256 amount = 100 ether;
        // vm.assume(amount > 0 && amount <= 1000 ether);
        
        IERC20 wstETH = IERC20(WSTETH);
        uint256 balance = testAssetUtils.get_wstETH(address(this), amount);

        (bool success, bytes memory result) = address(wrapper).delegatecall(
            abi.encodeWithSignature("unwrap(uint256,address)", balance, WSTETH)
        );
        require(success, "Delegatecall failed");
        (uint256 unwrappedAmount, IERC20 unwrappedToken) = abi.decode(result, (uint256, IERC20));

        assertEq(address(unwrappedToken), STETH, "Unwrapped token should be stETH");
        assertGt(unwrappedAmount, 0, "Unwrapped amount should be greater than 0");
        assertApproxEqRel(IERC20(STETH).balanceOf(address(this)), unwrappedAmount, 1e15, "Unwrapped amount should be approximately received");
    }

    function testWrapOETH() public {
        uint256 amount = 10 ether;
        
        IERC20 oETH = IERC20(OETH);
        uint256 balance = testAssetUtils.get_OETH(address(this), amount);
        oETH.approve(WOETH, balance);

        (bool success, bytes memory result) = address(wrapper).delegatecall(
            abi.encodeWithSignature("wrap(uint256,address)", balance, OETH)
        );
        require(success, "Delegatecall failed");
        (uint256 wrappedAmount, IERC20 wrappedToken) = abi.decode(result, (uint256, IERC20));

        assertEq(address(wrappedToken), WOETH, "Wrapped token should be woETH");
        assertGt(wrappedAmount, 0, "Wrapped amount should be greater than 0");
        assertEq(IERC20(WOETH).balanceOf(address(this)), wrappedAmount, "Wrapped amount should be received");
    }

    function testUnwrapWoETH() public {
        uint256 amount = 100 ether;
        
        IERC20 woETH = IERC20(WOETH);
        uint256 balance = testAssetUtils.get_wOETH(address(this), amount);

        (bool success, bytes memory result) = address(wrapper).delegatecall(
            abi.encodeWithSignature("unwrap(uint256,address)", balance, WOETH)
        );
        require(success, "Delegatecall failed");
        (uint256 unwrappedAmount, IERC20 unwrappedToken) = abi.decode(result, (uint256, IERC20));

        assertEq(address(unwrappedToken), OETH, "Unwrapped token should be oETH");
        assertGt(unwrappedAmount, 0, "Unwrapped amount should be greater than 0");
        assertApproxEqRel(IERC20(OETH).balanceOf(address(this)), unwrappedAmount, 1e15, "Unwrapped amount should be approximately received");
    }

}
