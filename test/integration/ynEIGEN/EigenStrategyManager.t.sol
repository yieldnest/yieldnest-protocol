// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./ynEigenIntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces//IPausable.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ynBase} from "src/ynBase.sol";
import "forge-std/console.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";


contract EigenStrategyManagerTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    address[10] public depositors;

    constructor() {
        testAssetUtils = new TestAssetUtils();
        for (uint i = 0; i < 10; i++) {
            depositors[i] = address(uint160(uint256(keccak256(abi.encodePacked("depositor", i)))));
        }
    }

    function testStakeAssetsToNodeSuccessFuzz(
        uint256 wstethAmount,
        uint256 woethAmount,
        uint256 rethAmount,
        uint256 sfrxethAmount
    ) public {

        // cannot call stakeAssetsToNode with any amount == 0. all must be non-zero.
        vm.assume(
            wstethAmount < 100 ether && wstethAmount >= 2 wei &&
            woethAmount < 100 ether && woethAmount >= 2 wei &&
            rethAmount < 100 ether && rethAmount >= 2 wei &&
            sfrxethAmount < 100 ether && sfrxethAmount >= 2 wei
        );

        // Setup: Create a token staking node and prepare assetsToDeposit
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);

        // uint256 wstethAmount = 18446744073709551616; // 1.844e19
        // uint256 woethAmount = 4918;
        // uint256 rethAmount = 5018;
        // uint256 sfrxethAmount = 17119; // 1.711e4

        uint256 assetCount = 4;

        // Call with arrays and from controller
        IERC20[] memory assetsToDeposit = new IERC20[](assetCount);
        assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        assetsToDeposit[1] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        assetsToDeposit[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assetsToDeposit[3] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256[] memory amounts = new uint256[](assetCount);
        amounts[0] = wstethAmount;
        amounts[1] = woethAmount;
        amounts[2] = rethAmount;
        amounts[3] = sfrxethAmount;

        for (uint256 i = 0; i < assetCount; i++) {
            address prankedUser = depositors[i];
            if (amounts[i] == 0) {
                // no deposits
                continue;
            }
            testAssetUtils.depositAsset(ynEigenToken, address(assetsToDeposit[i]), amounts[i], prankedUser);
        }

        uint256[] memory initialBalances = new uint256[](assetsToDeposit.length);
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            initialBalances[i] = assetsToDeposit[i].balanceOf(address(ynEigenToken));
        }

        uint256 totalAssetsBefore = ynEigenToken.totalAssets();       

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), assetsToDeposit, amounts);
        vm.stopPrank();

        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            uint256 initialBalance = initialBalances[i];
            uint256 finalBalance = assetsToDeposit[i].balanceOf(address(ynEigenToken));
            assertEq(initialBalance - finalBalance, amounts[i], "Balance of ynEigen did not decrease by the staked amount for asset");
            assertEq(compareWithThreshold(eigenStrategyManager.getStakedAssetBalance(assetsToDeposit[i]), initialBalance, 3), true, "Staked asset balance does not match initial balance within threshold");
            uint256 userUnderlyingView = eigenStrategyManager.strategies(assetsToDeposit[i]).userUnderlyingView(address(tokenStakingNode));

            uint256 expectedUserUnderlyingView = initialBalance;
            if (address(assetsToDeposit[i]) == chainAddresses.lsd.WSTETH_ADDRESS || address(assetsToDeposit[i]) == chainAddresses.lsd.WOETH_ADDRESS) {

                // TODO: come back to this to see why the reverse operation of converting the 
                // userUnderlyingView to the wrapped asset using the Rate Provider does not give the same result

                //expectedUserUnderlyingView = expectedUserUnderlyingView * wrappedAssetRate / 1e18;
                //userUnderlyingView = userUnderlyingView * 1e18 / wrappedAssetRate;
                if (address(assetsToDeposit[i]) == chainAddresses.lsd.WSTETH_ADDRESS) {
                    IwstETH wstETH = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS);
                    userUnderlyingView = wstETH.getWstETHByStETH(userUnderlyingView);
                } else if (address(assetsToDeposit[i]) == chainAddresses.lsd.WOETH_ADDRESS) {
                    IERC4626 woETH = IERC4626(chainAddresses.lsd.WOETH_ADDRESS);
                    userUnderlyingView = woETH.previewDeposit(userUnderlyingView);
                }
            }

            uint256 comparisonTreshold = 3;
            assertEq(compareWithThreshold(expectedUserUnderlyingView, userUnderlyingView, comparisonTreshold), true, "Initial balance does not match user underlying view within threshold");
        }

        uint256 totalAssetsAfter = ynEigenToken.totalAssets();
        assertEq(compareWithThreshold(totalAssetsBefore, totalAssetsAfter, 100), true, "Total assets before and after staking do not match within a threshold of 3");
    }

    function testExpectedStrategiesForAssets() public {
        address wstethAsset = chainAddresses.lsd.WSTETH_ADDRESS;
        address woethAsset = chainAddresses.lsd.WOETH_ADDRESS;
        address rethAsset = chainAddresses.lsd.RETH_ADDRESS;
        address sfrxethAsset = chainAddresses.lsd.SFRXETH_ADDRESS;
        address expectedStrategyForWSTETH = chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS;
        address expectedStrategyForWOETH = chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS;
        address expectedStrategyForRETH = chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS;
        address expectedStrategyForSFRXETH = chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS;

        assertEq(address(eigenStrategyManager.strategies(IERC20(wstethAsset))), expectedStrategyForWSTETH, "Incorrect strategy for WSTETH");
        assertEq(address(eigenStrategyManager.strategies(IERC20(woethAsset))), expectedStrategyForWOETH, "Incorrect strategy for WOETH");
        assertEq(address(eigenStrategyManager.strategies(IERC20(rethAsset))), expectedStrategyForRETH, "Incorrect strategy for RETH");
        assertEq(address(eigenStrategyManager.strategies(IERC20(sfrxethAsset))), expectedStrategyForSFRXETH, "Incorrect strategy for SFRXETH");
    }

    function testAddStrategySuccess() public {
        vm.prank(address(0x1)); // Assuming address(0x1) has STRATEGY_ADMIN_ROLE
        IERC20 newAsset = IERC20(address(0x123)); // Example new asset address
        IStrategy newStrategy = IStrategy(address(0x456)); // Example new strategy address

        // Initially, there should be no strategy set for newAsset
        assertEq(address(eigenStrategyManager.strategies(newAsset)), address(0), "Strategy already set for new asset");

        // Add strategy for newAsset
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.addStrategy(newAsset, newStrategy);

        // Verify that the strategy has been set
        assertEq(address(eigenStrategyManager.strategies(newAsset)), address(newStrategy), "Strategy not set correctly");
    }

    function testAddStrategyFailureAlreadySet() public {
        IERC20 existingAsset = IERC20(address(0x123)); // Example existing asset address
        IStrategy existingStrategy = IStrategy(address(0x456)); // Example existing strategy address

        // Setup: Add a strategy initially
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.addStrategy(existingAsset, existingStrategy);


        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        // Attempt to add the same strategy again should fail
        vm.expectRevert(abi.encodeWithSelector(EigenStrategyManager.StrategyAlreadySetForAsset.selector, address(existingAsset)));
        eigenStrategyManager.addStrategy(existingAsset, existingStrategy);
    }

    function testAddStrategyFailureZeroAsset() public {
        IStrategy newStrategy = IStrategy(address(0x456)); // Example new strategy address

        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        // Test with zero address for asset
        vm.expectRevert(abi.encodeWithSelector(EigenStrategyManager.ZeroAddress.selector));
        eigenStrategyManager.addStrategy(IERC20(address(0)), newStrategy);
    }

    function testAddStrategyFailureZeroStrategy() public {
        IERC20 newAsset = IERC20(address(0x123)); // Example new asset address

        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(EigenStrategyManager.ZeroAddress.selector));
        eigenStrategyManager.addStrategy(newAsset, IStrategy(address(0)));
    }
}