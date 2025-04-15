 // SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "test/integration/ynEIGEN/WithSlashingBase.t.sol";

contract EigenStrategyManagerWithSlashingTest is WithSlashingBase {
    function testStakeNodesAndSlash(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);

        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);

        // slash 50%
        _slash(slashingPercentage);
        
        // update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        
        assertApproxEqRel(stakeAfter, stakeBefore * (1 ether - slashingPercentage) / 1e18, 1, "Assets should have been staked by half");
    }
    
    function testStakeNodesAndSlashWithoutSync(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);
        
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);

        // slash by slashingPercentage
        _slash(slashingPercentage);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        
        assertApproxEqRel(stakeAfter, stakeBefore, 1, "Assets should have been stay unchanged without sync");
    }
    
    function testQueuedDepositsAndSlash(uint256 slashingPercentage) public {
        vm.assume(slashingPercentage > 0 && slashingPercentage <= 1e18);
        
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        (, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        _slash(slashingPercentage);

        // update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        
        assertApproxEqRel(stakeAfter, stakeBefore * (1 ether - slashingPercentage) / 1e18, 1, "Assets should have been reduced according to slashing percentage");
    }
}