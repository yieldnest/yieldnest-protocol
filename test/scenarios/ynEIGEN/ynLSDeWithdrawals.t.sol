// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./ynLSDeUpgradeScenario.sol";

contract ynLSDeWithdrawalsTest is ynLSDeUpgradeScenario {

    address public constant user = address(0x42069);

    function setUp() public override {
        super.setUp();

        // upgrades the contracts
        {
            test_Upgrade_AllContracts_Batch();
            test_Upgrade_TokenStakingNodeImplementation_Scenario();
        }

        // deal assets to user
        {
            deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.RETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1 ether });
        }
    }

    function testSanity() public {
        _setupTokenStakingNode(1 ether);
    }

    function _setupTokenStakingNode(uint256 _amount) private {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode _tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        uint256 _len = 3;
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        _assetsToDeposit[1] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        _assetsToDeposit[2] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256[] memory _amounts = new uint256[](_len);
        _amounts[0] = _amount;
        _amounts[1] = _amount;
        _amounts[2] = _amount;

        vm.startPrank(user);
        for (uint256 i = 0; i < _len; i++) {
            _assetsToDeposit[i].approve(address(yneigen), _amounts[i]);
            yneigen.deposit(_assetsToDeposit[i], _amounts[i], user);
        }
        vm.stopPrank();

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(_tokenStakingNode.nodeId(), _assetsToDeposit, _amounts);
        vm.stopPrank();
    }

    // queueWithdrawals
    // completeQueuedWithdrawals
    // processPrincipalWithdrawals
    // requestWithdrawal
    // claimWithdrawal
}