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

contract EigenStrategyManagerTest is ynEigenIntegrationBaseTest {

    function testStakeAssetsToNodeSuccess() public {
        // Setup: Create a token staking node and prepare assets
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);

        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 stakeAmount = 50 ether;

        // User obtains wstETH and approves ynEigenToken for staking
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 obtainedAmount = testAssetUtils.get_wstETH(address(this), stakeAmount);
        asset.approve(address(ynEigenToken), obtainedAmount);

        // Depositor deposits the staked assets to the node
        ynEigenToken.deposit(asset, obtainedAmount, address(tokenStakingNode));

        uint256 nodeId = tokenStakingNode.nodeId();
        // Call with arrays and from controller
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = obtainedAmount;
        uint256 initialBalance = asset.balanceOf(address(ynEigenToken));
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        uint256 finalBalance = asset.balanceOf(address(ynEigenToken));
        assertEq(initialBalance - finalBalance, obtainedAmount, "Balance of ynEigen did not decrease by the staked amount");
    }
}