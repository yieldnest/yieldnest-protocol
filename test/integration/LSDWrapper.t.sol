// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {IWithdrawalQueueManager} from "../../src/interfaces/IWithdrawalQueueManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestAssetUtils} from "../utils/TestAssetUtils.sol";


contract LSDWrapperTest is Test {
    LSDWrapper public wrapper;
    IERC20 public stETH;
    IERC20 public OETH;
    address public withdrawalQueueManager;
    IERC20 public wstETH;
    function setUp() public {

        // Mainnet addresses
        stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        OETH = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
        wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        withdrawalQueueManager = 0xF1288046f5A4bfA1a9D1Dc0D81e3B72A1c5CBe12;

        wrapper = new LSDWrapper(
            address(wstETH), // wstETH address
            address(0xDcEe70654261AF21C44c093C300eD3Bb97b78192), // woETH address
            address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3), // oETH address
            address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)  // stETH address
        );
        wrapper.initialize();
    }

    function testWrap() public {
        uint256 wrapAmount = 1000 * 1e18;
        // Get stETH from Lido's stETH contract
        (bool success, ) = address(stETH).call{value: wrapAmount}("");
        require(success, "Failed to get stETH");
        stETH.approve(address(wrapper), wrapAmount);



        wrapper.wrap(wrapAmount, stETH);
    }

    function testUnwrapWithoutTransferUsingDelegateCall() public {
        uint256 wrapAmount = 1000 * 1e18;
        // Get stETH from Lido's stETH contract
        (bool success, ) = address(stETH).call{value: wrapAmount}("");
        require(success, "Failed to get stETH");
        stETH.approve(address(wrapper), wrapAmount);

        // Wrap stETH to wstETH
        (uint256 wrappedAmount, IERC20 wrappedToken) = wrapper.wrap(wrapAmount, stETH);
        
        // Prepare the calldata for unwrapWithoutTransfer
        bytes memory callData = abi.encodeWithSelector(
            LSDWrapper.unwrapWithoutTransfer.selector,
            wrappedAmount,
            wrappedToken
        );

        // Perform delegatecall to unwrapWithoutTransfer
        (bool delegateCallSuccess, bytes memory returnData) = address(wrapper).delegatecall(callData);
        require(delegateCallSuccess, "Delegatecall failed");

        // Decode the returned values
        (uint256 unwrappedAmount, IERC20 unwrappedToken) = abi.decode(returnData, (uint256, IERC20));

        // Assert the results
        assertEq(address(unwrappedToken), address(stETH), "Unwrapped token should be stETH");
        assertApproxEqRel(unwrappedAmount, wrapAmount, 1e15, "Unwrapped amount should be approximately equal to wrap amount");
    }

    function testWrapWithoutTransferUsingDelegateCall() public {
        uint256 wrapAmount = 1000 * 1e18;
        // Get stETH from Lido's stETH contract
        (bool success, ) = address(stETH).call{value: wrapAmount}("");
        require(success, "Failed to get stETH");

        // Prepare the calldata for wrapWithoutTransfer
        bytes memory callData = abi.encodeWithSelector(
            LSDWrapper.wrapWithoutTransfer.selector,
            wrapAmount,
            stETH
        );

        // Perform delegatecall to wrapWithoutTransfer
        (bool delegateCallSuccess, bytes memory returnData) = address(wrapper).delegatecall(callData);
        require(delegateCallSuccess, "Delegatecall failed");

        // Decode the returned values
        (uint256 wrappedAmount, IERC20 wrappedToken) = abi.decode(returnData, (uint256, IERC20));

        // Assert the results
        assertEq(address(wrappedToken), address(wstETH), "Wrapped token should be wstETH");
        assertGt(wrappedAmount, 0, "Wrapped amount should be greater than zero");
        assertLt(wrappedAmount, wrapAmount, "Wrapped amount should be less than wrap amount due to exchange rate");

        // Verify the balance of wstETH in the wrapper contract
        assertEq(wstETH.balanceOf(address(this)), wrappedAmount, "Wrapper should have the wrapped amount of wstETH");
    }
}
