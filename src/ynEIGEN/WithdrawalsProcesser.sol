// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

contract withdrawalsProcesser {

    function getRektNodes() public view returns (uint256[] memory _rektNodes, address[] memory _rektStrats) {

        uint256 _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        if (_pendingWithdrawalRequests == 0) return;

        address[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        address[] memory _assets = assetRegistry.getAssets();

        // NOTE: this could also be reversed if we want to optimize for nodes instead of assets (worse ux though)
        for (uint256 i = 0; i < _assets.length; i++) {
            address _strategy = _assets[i].getStrategy();
            for (uint256 j = 0; j < _nodes.length; j++) {
                uint256 _shares = _strategy.shares(_nodes[i]);
                uint256 _sharesToUnit = _getUnit(_shares, _strategy);
                if (_sharesToUnit >= _pendingWithdrawalRequests) {
                    _rektNodes.push(_nodes[i]);
                    _rektStrats.push(_strategy);
                    return;
                } else if (_sharesToUnit > threshold) {
                    _pendingWithdrawalRequests -= _sharesToUnit;
                    _rektNodes.push(_nodes[i]);
                    _rektStrats.push(_strategy);
                }
            }
        }
    }

    function queueWithdrawals(uint256[] calldata _nodes, address[] calldata _strats) public onlyOwner {
        // queue withdrawals according to keeper input and save data for `completeQueuedWithdrawals`
    }

    function completeQueuedWithdrawals() public {
        // complete withdrawals according to data saved in `queueWithdrawals`
    }

    function processPrincipalWithdrawals() public {
        // 1. check pending withdrawal requests
        // 2. send everything to queue if can't satisfy (or can satisfy everything without extra)
        // 3. if extra, reinvest
    }

    //
    //
    //

    function updateThreshold() public onlyOwner {}
}