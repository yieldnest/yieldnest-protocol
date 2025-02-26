 // SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./WithSlashingBase.t.sol";

contract EigenStrategyManagerWithSlashing is WithSlashingBase {
    function testStakeNodesAndSlash() public {
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);

        {
            // slash 50%
            _slash(0.5 ether);
            
            // update balances after slashing
            ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
            nodes[0] = tokenStakingNode;
            eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
            
            (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
            
            assertApproxEqRel(stakeAfter, stakeBefore / 2, 1, "Assets should have been staked by half");
        }
    }
    
    function testStakeNodesAndSlashWithoutSync() public {
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);

        {
            // slash 50%
            _slash(0.5 ether);
            
            (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
            
            assertApproxEqRel(stakeAfter, stakeBefore, 1, "Assets should have been stay unchanged without sync");
        }
    }
    
    function testQueuedDepositsAndSlash() public {
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        // update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        
        assertApproxEqRel(stakeAfter, stakeBefore, 1, "Assets should have been staked by half");
    }
}