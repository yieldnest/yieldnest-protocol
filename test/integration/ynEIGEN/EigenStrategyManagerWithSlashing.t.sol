 // SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "test/integration/ynEIGEN/WithSlashingBase.t.sol";

contract EigenStrategyManagerWithSlashingTest is WithSlashingBase {

    address[10] public depositors;

    constructor() WithSlashingBase() {
        for (uint256 i = 0; i < 10; i++) {
            depositors[i] = address(uint160(uint256(keccak256(abi.encodePacked("depositor", i)))));
        }
    }

    function testStakeNodesAndSlash(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);

        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsBefore = ynEigenToken.totalAssets();

        // slash by slashingPercentage
        _slash(slashingPercentage);
        
        // update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsAfter = ynEigenToken.totalAssets();
        
        assertApproxEqRel(stakeAfter, stakeBefore * (1 ether - slashingPercentage) / 1e18, 1, "Assets should have been reduced according to slashing percentage");
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore * (1 ether - slashingPercentage) / 1e18, 1, "Total assets should have been reduced according to slashing percentage");
    }
    
    function testStakeNodesAndSlashWithoutSync(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);
        
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsBefore = ynEigenToken.totalAssets();

        // slash by slashingPercentage
        _slash(slashingPercentage);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsAfter = ynEigenToken.totalAssets();
        
        assertApproxEqRel(stakeAfter, stakeBefore, 1, "Assets should have been stay unchanged without sync");
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore, 1, "Total assets should remain unchanged without sync");
    }
    
    function testQueuedDepositsAndSlash(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);
        
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsBefore = ynEigenToken.totalAssets();
        (, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        _slash(slashingPercentage);

        // update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        uint256 totalAssetsAfter = ynEigenToken.totalAssets();
        
        assertApproxEqRel(stakeAfter, stakeBefore * (1 ether - slashingPercentage) / 1e18, 1, "Assets should have been reduced according to slashing percentage");
        assertApproxEqRel(totalAssetsAfter, totalAssetsBefore * (1 ether - slashingPercentage) / 1e18, 1, "Total assets should have been reduced according to slashing percentage");
    }



    function testStakeMultipleAssetsAndSlash(
        // uint256 wstethAmount,
        // uint256 woethAmount,
        // uint256 rethAmount,
        // uint256 sfrxethAmount
    ) public {

        // cannot call stakeAssetsToNode with any amount == 0. all must be non-zero.
        // vm.assume(
        //     wstethAmount < 100 ether && wstethAmount >= 2 wei &&
        //     woethAmount < 100 ether && woethAmount >= 2 wei &&
        //     rethAmount < 100 ether && rethAmount >= 2 wei &&
        //     sfrxethAmount < 100 ether && sfrxethAmount >= 2 wei
        // );

        // Set all amounts to 100 ether
        uint256 wstethAmount = 100 ether;
        uint256 woethAmount = 100 ether;
        uint256 rethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // Setup: Create a token staking node and prepare assetsToDeposit
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);

        uint256 assetCount = _isHolesky() ? 3 : 4;

        // Call with arrays and from controller
        IERC20[] memory assetsToDeposit = new IERC20[](assetCount);
        assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        assetsToDeposit[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        if (!_isHolesky()) assetsToDeposit[3] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

        uint256[] memory amounts = new uint256[](assetCount);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        amounts[2] = rethAmount;
        if (!_isHolesky()) amounts[3] = woethAmount;

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


        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), assetsToDeposit, amounts);
        vm.stopPrank();

        uint256 totalAssetsBefore = ynEigenToken.totalAssets();
        
        // Get balances before slashing
        uint256[] memory stakesBefore = new uint256[](assetsToDeposit.length);
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assetsToDeposit[i]);
            (stakesBefore[i],) = eigenStrategyManager.strategiesBalance(strategy);
        }
        
        // Perform slashing
        // Slash all 4 strategies
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assetsToDeposit[i]);
            _slash(0.5 ether, strategy);
        }
        
        // Update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        // Assert balances were reduced by 50%
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assetsToDeposit[i]);
            (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(strategy);
            
            assertApproxEqRel(stakeAfter, stakesBefore[i] * 0.5 ether / 1e18, 1, "Assets should have been reduced by 50%");
        }

        // Assert that total assets after slashing are reduced by the slashing factor (50%)
        uint256 totalAssetsAfter = ynEigenToken.totalAssets();

        assertApproxEqRel(
                totalAssetsAfter,
                totalAssetsBefore * 0.5 ether / 1e18,
                1e17,
                "Total assets should have been reduced by 50% after slashing"
        );
    }
}