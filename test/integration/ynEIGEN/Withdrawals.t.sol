// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {WithdrawalsProcessor} from "../../../src/ynEIGEN/withdrawalsProcessor.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";

import "./ynEigenIntegrationBaseTest.sol";

contract WithdrawalsTest is ynEigenIntegrationBaseTest {

    bool private _setup = true;

    address public constant user = address(0x42069);
    address public constant owner = address(0x42069420);

    ITokenStakingNode public tokenStakingNode;
    WithdrawalsProcessor public withdrawalsProcessor;

    function setUp() public virtual override {

        super.setUp();

        // deal assets to user
        {
            deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether });
            deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether });
            deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether });
        }

        // unpause transfers
        {
            vm.prank(actors.admin.UNPAUSE_ADMIN);
            ynEigenToken.unpauseTransfers();
        }

        // grant burner role
        {
            vm.startPrank(actors.admin.STAKING_ADMIN);
            ynEigenToken.grantRole(ynEigenToken.BURNER_ROLE(), address(withdrawalQueueManager));
            vm.stopPrank();
        }

        // // user depost
        // {
        //     uint256 _amount = 100 ether;

        //     vm.startPrank(user);

        //     // deposit wsteth
        //     {
        //         IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(ynEigenToken), _amount);
        //         ynEigenToken.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), _amount, user);
        //     }

        //     // deposit woeth
        //     {
        //         IERC20(chainAddresses.lsd.WOETH_ADDRESS).approve(address(ynEigenToken), _amount);
        //         ynEigenToken.deposit(IERC20(chainAddresses.lsd.WOETH_ADDRESS), _amount, user);
        //     }

        //     // deposit sfrxeth
        //     {
        //         IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).approve(address(ynEigenToken), _amount);
        //         ynEigenToken.deposit(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS), _amount, user);
        //     }
        //     vm.stopPrank();
        // }

        // // request withdrawl
        // {
        //     uint256 _balance = ynEigenToken.balanceOf(user);
        //     vm.startPrank(user);
        //     ynEigenToken.approve(address(withdrawalQueueManager), _balance);
        //     withdrawalQueueManager.requestWithdrawal(_balance);
        //     vm.stopPrank();
        // }

        // // top up redemptionAssetsVault
        // {
        //     address _topper = address(0x420420);
        //     uint256 _amount = 50; // 50 wei
        //     deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: _topper, give: _amount });
        //     deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: _topper, give: _amount });
        //     deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: _topper, give: _amount });
        //     vm.startPrank(_topper);
        //     IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
        //     redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WSTETH_ADDRESS);
        //     IERC20(chainAddresses.lsd.WOETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
        //     redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WOETH_ADDRESS);
        //     IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
        //     redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.SFRXETH_ADDRESS);
        //     vm.stopPrank();
        // }

        // deploy withdrawalsProcessor
        {
            withdrawalsProcessor = new WithdrawalsProcessor(
                owner,
                address(withdrawalQueueManager),
                address(tokenStakingNodesManager),
                address(assetRegistry),
                address(eigenStrategyManager),
                address(eigenLayer.delegationManager)
            );
        }

        // grant withdrawer role to withdrawalsProcessor
        {
            vm.startPrank(actors.wallets.YNSecurityCouncil);
            eigenStrategyManager.grantRole(eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor));
            vm.stopPrank();
        }
    }

    function testSanity() public {
        assertTrue(true, "testSanity: E0");
    }

    //
    // queueWithdrawals
    //

    function testQueueWithdrawalSTETH(uint256 _amount) public {
        if (_setup) setup_(_amount);

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        uint256 _shares = _strategy.shares((address(tokenStakingNode)));

        uint256 _totalAssetsBefore = ynEigenToken.totalAssets();

        // vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        // tokenStakingNode.queueWithdrawals(_strategy, _shares);
        vm.prank(owner);
        withdrawalsProcessor.queueWithdrawals();

        assertEq(ynEigenToken.totalAssets(), _totalAssetsBefore, "testQueueWithdrawalSTETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), _shares, "testQueueWithdrawalSTETH: E1");
    }

    //
    // internal helpers
    //

    // (1) create token staking node
    // (2) user deposit
    // (3) stake assets to node
    // (4) user request withdrawal
    function setup_(uint256 _amount) private {
        vm.assume(_amount > 10_000 && _amount < 100 ether);

        // create token staking node
        {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();
        }

        // user deposit

        uint256 _len = 3;
        uint256[] memory _amounts = new uint256[](_len);
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        {
            _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            _assetsToDeposit[1] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
            _assetsToDeposit[2] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

            _amounts[0] = _amount;
            _amounts[1] = _amount;
            _amounts[2] = _amount;

            vm.startPrank(user);
            for (uint256 i = 0; i < _len; i++) {
                _assetsToDeposit[i].approve(address(ynEigenToken), _amounts[i]);
                ynEigenToken.deposit(_assetsToDeposit[i], _amounts[i], user);
            }
            vm.stopPrank();
        }

        // stake assets to node
        {
            vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), _assetsToDeposit, _amounts);
            vm.stopPrank();
        }

        // request withdrawl
        {
            uint256 _balance = ynEigenToken.balanceOf(user);
            vm.startPrank(user);
            ynEigenToken.approve(address(withdrawalQueueManager), _balance);
            withdrawalQueueManager.requestWithdrawal(_balance);
            vm.stopPrank();
        }
    }
}