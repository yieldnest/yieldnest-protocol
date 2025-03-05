// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";
import {IWithdrawalsProcessor} from "../../../src/interfaces/IWithdrawalsProcessor.sol";

import {WithdrawalsProcessor} from "../../../src/ynEIGEN/WithdrawalsProcessor.sol";

import "./ynEigenIntegrationBaseTest.sol";

contract WithdrawalsProcessorTest is ynEigenIntegrationBaseTest {

    uint256 tokenId;

    bool private _setup = true;

    ITokenStakingNode public tokenStakingNode;
    IWithdrawalsProcessor public withdrawalsProcessor;

    IStrategy private _stethStrategy;
    IStrategy private _oethStrategy;
    IStrategy private _sfrxethStrategy;

    address public constant user = address(0x42069);
    address public constant owner = address(0x42069420);
    address public constant keeper = address(0x4206942069);
    
    uint256 AMOUNT = 50 ether;

    function setUp() public virtual override {
        super.setUp();

        // deal assets to user
        {
            deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether});
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

        // deploy withdrawalsProcessor
        {
            withdrawalsProcessor = new WithdrawalsProcessor(
                address(withdrawalQueueManager),
                address(tokenStakingNodesManager),
                address(assetRegistry),
                address(eigenStrategyManager),
                address(eigenLayer.delegationManager),
                address(ynEigenToken),
                address(redemptionAssetsVault),
                address(wrapper),
                chainAddresses.lsd.STETH_ADDRESS,
                chainAddresses.lsd.WSTETH_ADDRESS,
                chainAddresses.lsd.OETH_ADDRESS,
                chainAddresses.lsd.WOETH_ADDRESS
            );

            withdrawalsProcessor = WithdrawalsProcessor(address(new TransparentUpgradeableProxy(address(withdrawalsProcessor), actors.admin.PROXY_ADMIN_OWNER, "")));

            WithdrawalsProcessor(address(withdrawalsProcessor)).initialize(owner, keeper);
        }

        // grant roles to withdrawalsProcessor
        {
            vm.startPrank(actors.wallets.YNSecurityCouncil);
            eigenStrategyManager.grantRole(
                eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor)
            );
            eigenStrategyManager.grantRole(
                eigenStrategyManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor)
            );
            withdrawalQueueManager.grantRole(
                withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(withdrawalsProcessor)
            );
            vm.stopPrank();
        }

        // set some vars
        {
            _stethStrategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
            _oethStrategy = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);
            _sfrxethStrategy = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
        }
    }

    //
    // queueWithdrawals
    //
    function testQueueWithdrawal() public {
        _queueWithdrawal(AMOUNT);
    }

    //
    // completeQueuedWithdrawals
    //
    function testCompleteQueuedWithdrawals() public {
        _completeQueuedWithdrawals(AMOUNT);
    }

    //
    // processPrincipalWithdrawals
    //
    function testProcessPrincipalWithdrawals() public {
        _processPrincipalWithdrawals(AMOUNT);
    }

    //
    // claimWithdrawal
    //
    function testClaimWithdrawal() public {
        _processPrincipalWithdrawals(AMOUNT);

        uint256 _userStethBalanceBefore = IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user);
        uint256 _userSfrxethBalanceBefore = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user);

        _topUpRedemptionAssetsVault();

        vm.prank(user);
        withdrawalQueueManager.claimWithdrawal(tokenId, user);

        uint256 _expectedAmount = AMOUNT * (1_000_000 - withdrawalQueueManager.withdrawalFee()) / 1_000_000;
        assertApproxEqAbs(
            IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user),
            _userStethBalanceBefore + _expectedAmount,
            1e4,
            "testClaimWithdrawal: E0"
        );
        if (!_isHolesky()) {
            uint256 _userOethBalanceBefore = IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user);
            assertApproxEqAbs(
                IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user),
                _userOethBalanceBefore + _expectedAmount,
                1e4,
                "testClaimWithdrawal: E1"
            );
        }
        assertApproxEqAbs(
            IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user),
            _userSfrxethBalanceBefore + _expectedAmount,
            1e4,
            "testClaimWithdrawal: E2"
        );
    }

    //
    // private helpers
    //
    
    function _completeQueuedWithdrawals(uint256 _amount) internal {
        _queueWithdrawal(_amount);

        // skip withdrawal delay
        {
            assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E0");
            vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
        }

        // complete queued withdrawals -- sfrxeth
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E1");

            vm.prank(keeper);
            withdrawalsProcessor.completeQueuedWithdrawals();

            assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), 0, "completeQueuedWithdrawals: E2");
            assertEq(withdrawalsProcessor.ids().completed, 1, "completeQueuedWithdrawals: E3");
        }

        // complete queued withdrawals -- steth
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E4");

            vm.prank(keeper);
            withdrawalsProcessor.completeQueuedWithdrawals();

            assertEq(tokenStakingNode.queuedShares(_stethStrategy), 0, "completeQueuedWithdrawals: E5");
            assertEq(withdrawalsProcessor.ids().completed, 2, "completeQueuedWithdrawals: E6");
        }

        if (!_isHolesky()) {
            // complete queued withdrawals -- oeth
            {
                assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E7");

                vm.prank(keeper);
                withdrawalsProcessor.completeQueuedWithdrawals();

                assertEq(tokenStakingNode.queuedShares(_oethStrategy), 0, "completeQueuedWithdrawals: E8");
                assertEq(withdrawalsProcessor.ids().completed, 3, "completeQueuedWithdrawals: E9");
            }
        }

        assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "completeQueuedWithdrawals: E10");
    }
    
    function _queueWithdrawal(uint256 _amount) internal {
        if (_setup) setup_(_amount);

        uint256 _sfrxethShares = _sfrxethStrategy.shares((address(tokenStakingNode)));
        uint256 _stethShares = _stethStrategy.shares((address(tokenStakingNode)));
        uint256 _oethShares;
        if (!_isHolesky()) {
            _oethShares = _oethStrategy.shares((address(tokenStakingNode)));
        }

        bool _queuedEverything;

        // 1st queue withdrawals -- sfrxeth
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E0");
            (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) =
                withdrawalsProcessor.getQueueWithdrawalsArgs();
            vm.prank(keeper);
            _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

            assertFalse(_queuedEverything, "queueWithdrawal: E1");
            assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), _sfrxethShares, "queueWithdrawal: E2");
            assertEq(withdrawalsProcessor.batch(0), 1, "queueWithdrawal: E3");

            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(0);
            assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E4");
            assertEq(address(_queuedWithdrawal.strategy), address(_sfrxethStrategy), "queueWithdrawal: E5");
            assertEq(_queuedWithdrawal.nonce, 0, "queueWithdrawal: E6");
            assertEq(_queuedWithdrawal.shares, _sfrxethShares, "queueWithdrawal: E7");
            assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E8");
            assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E9");
        }

        // 2nd queue withdrawals -- steth
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E10");
            (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) =
                withdrawalsProcessor.getQueueWithdrawalsArgs();
            vm.prank(keeper);
            _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

            assertTrue(_queuedEverything, "queueWithdrawal: E11");
            assertEq(tokenStakingNode.queuedShares(_stethStrategy), _stethShares, "queueWithdrawal: E12");
            assertEq(withdrawalsProcessor.batch(1), 2, "queueWithdrawal: E13");

            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(1);
            assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E14");
            assertEq(address(_queuedWithdrawal.strategy), address(_stethStrategy), "queueWithdrawal: E15");
            assertEq(_queuedWithdrawal.nonce, 1, "queueWithdrawal: E16");
            assertEq(_queuedWithdrawal.shares, _stethShares, "queueWithdrawal: E17");
            assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E18");
            assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E19");
        }
        
        // 3rd queue withdrawals -- oeth
        {
            if (!_isHolesky()) {
                assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "queueWithdrawal: E20");
                (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) =
                    withdrawalsProcessor.getQueueWithdrawalsArgs();
                vm.prank(keeper);
                _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

                assertFalse(_queuedEverything, "queueWithdrawal: E21");
                assertEq(tokenStakingNode.queuedShares(_oethStrategy), _oethShares, "queueWithdrawal: E22");
                assertEq(withdrawalsProcessor.batch(2), 3, "queueWithdrawal: E23");

                WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                    IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(2);
                assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "queueWithdrawal: E24");
                assertEq(address(_queuedWithdrawal.strategy), address(_oethStrategy), "queueWithdrawal: E5");
                assertEq(_queuedWithdrawal.nonce, 2, "queueWithdrawal: E26");
                assertEq(_queuedWithdrawal.shares, _oethShares, "queueWithdrawal: E27");
                assertEq(_queuedWithdrawal.startBlock, block.number, "queueWithdrawal: E28");
                assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E29");
            }
        }

        // none
        {
            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(3);
            assertEq(address(_queuedWithdrawal.node), address(0), "queueWithdrawal: E25");
            assertEq(address(_queuedWithdrawal.strategy), address(0), "queueWithdrawal: E26");
            assertEq(_queuedWithdrawal.nonce, 0, "queueWithdrawal: E27");
            assertEq(_queuedWithdrawal.shares, 0, "queueWithdrawal: E28");
            assertEq(_queuedWithdrawal.startBlock, 0, "queueWithdrawal: E29");
            assertEq(_queuedWithdrawal.completed, false, "queueWithdrawal: E30");
        }

        assertEq(
            withdrawalsProcessor.totalQueuedWithdrawals(),
            withdrawalQueueManager.pendingRequestedRedemptionAmount(),
            "queueWithdrawal: E31"
        );
        
        assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "queueWithdrawal: E32");
    }
    
    function _processPrincipalWithdrawals(uint256 _amount) internal {
        _completeQueuedWithdrawals(_amount);

        // process principal withdrawals -- steth
        {
            assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E0");

            vm.prank(keeper);
            withdrawalsProcessor.processPrincipalWithdrawals();
        }

        // process principal withdrawals -- sfrxeth
        {
            assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E1");

            vm.prank(keeper);
            withdrawalsProcessor.processPrincipalWithdrawals();
        }
        
        if (!_isHolesky()) {
            // process principal withdrawals -- oeth
            {
                assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E2");

                vm.prank(keeper);
                withdrawalsProcessor.processPrincipalWithdrawals();
            }
        }

        assertFalse(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "processPrincipalWithdrawals: E3");
        assertEq(withdrawalsProcessor.totalQueuedWithdrawals(), 0, "processPrincipalWithdrawals: E4");
    }

    // (1) create token staking node
    // (2) user deposit
    // (3) stake assets to node
    // (4) user request withdrawal
    function setup_(uint256 _amount) private {
        // create token staking node
        {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();
        }

        // user deposit

        uint256 _len = _isHolesky() ? 2 : 3;
        uint256[] memory _amounts = new uint256[](_len);
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        {
            _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            _assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
            if (!_isHolesky()) _assetsToDeposit[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

            _amounts[0] = _amount;
            _amounts[1] = _amount;
            if (!_isHolesky()) _amounts[2] = _amount;

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

        // request withdrawal
        {
            uint256 _balance = ynEigenToken.balanceOf(user);
            vm.startPrank(user);
            ynEigenToken.approve(address(withdrawalQueueManager), _balance);
            tokenId = withdrawalQueueManager.requestWithdrawal(_balance);
            vm.stopPrank();
        }
    }

    function _topUpRedemptionAssetsVault() private {
        address _topper = address(0x4204206969);
        uint256 _amount = 50; // 50 wei
        deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: _topper, give: _amount});
        deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: _topper, give: _amount});
        deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: _topper, give: _amount});
        vm.startPrank(_topper);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
        redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WSTETH_ADDRESS);
        if (!_isHolesky()) {
            IERC20(chainAddresses.lsd.WOETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
            redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.WOETH_ADDRESS);
        }
        IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).approve(address(redemptionAssetsVault), _amount);
        redemptionAssetsVault.deposit(_amount, chainAddresses.lsd.SFRXETH_ADDRESS);
        vm.stopPrank();
    }

}
