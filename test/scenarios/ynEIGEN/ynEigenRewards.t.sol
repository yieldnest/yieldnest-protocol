// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import "./ynLSDeScenarioBaseTest.sol";

contract ynEigenRewardsTest is ynLSDeScenarioBaseTest {
    bool private _setup = true;

    address public constant user = address(0x42069);

    ITokenStakingNode public tokenStakingNode;

    function setUp() public virtual override {
        super.setUp();
    }

    function testTotalAssetsIsTheSameOverTime() public {

        uint256 AMOUNT = 10 ether;
        // Deal assets to user
        deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: AMOUNT});
        
        // User deposits assets
        vm.startPrank(user);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(ynEigenDepositAdapter_), AMOUNT);
        ynEigenDepositAdapter_.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), AMOUNT, user);
        vm.stopPrank();

        eigenStrategyManager.synchronizeNodesAndUpdateBalances(tokenStakingNodesManager.getAllNodes());
        
        // Measure initial total assets
        uint256 initialTotalAssets = yneigen.totalAssets();
        
        // Advance time by 1 month (30 days)
        vm.warp(block.timestamp + 30 days);


        eigenStrategyManager.synchronizeNodesAndUpdateBalances(tokenStakingNodesManager.getAllNodes());

        // Assert that assets have grown (rewards accrued)
        assertEq(yneigen.totalAssets(), initialTotalAssets, "Assets should grow over time due to rewards");
    }
    
}