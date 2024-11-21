// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {WithdrawalsProcessor} from "../../../src/ynEIGEN/withdrawalsProcessor.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";

import "./ynEigenIntegrationBaseTest.sol";
import "forge-std/console.sol";

interface IWithdrawalsProcessor { // @todo - move to interfaces
    function shouldQueueWithdrawals() external view returns (bool);
    function getQueueWithdrawalsArgs() external view returns (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares);
    function queueWithdrawals(IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _amounts) external returns (bool);
    function queuedWithdrawals(uint256 _id) external view returns (WithdrawalsProcessor.QueuedWithdrawal memory);
}

contract WithdrawalsProcessorTest is ynEigenIntegrationBaseTest {

    bool private _setup = true;

    address public constant user = address(0x42069);
    address public constant owner = address(0x42069420);

    ITokenStakingNode public tokenStakingNode;
    WithdrawalsProcessor public withdrawalsProcessor;

    IStrategy private _stethStrategy;
    IStrategy private _oethStrategy;
    IStrategy private _sfrxethStrategy;

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

        // deploy withdrawalsProcessor
        {
            withdrawalsProcessor = new WithdrawalsProcessor(
                owner,
                address(withdrawalQueueManager),
                address(tokenStakingNodesManager),
                address(assetRegistry),
                address(eigenStrategyManager),
                address(eigenLayer.delegationManager),
                address(ynEigenToken),
                address(redemptionAssetsVault),
                address(wrapper)
            );
        }

        // grant withdrawer role to withdrawalsProcessor
        {
            vm.startPrank(actors.wallets.YNSecurityCouncil);
            eigenStrategyManager.grantRole(eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor));
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

    function testQueueWithdrawal(uint256 _amount) public {
        if (_setup) setup_(_amount);

        uint256 _stethShares = _stethStrategy.shares((address(tokenStakingNode)));
        uint256 _oethShares = _oethStrategy.shares((address(tokenStakingNode)));
        uint256 _sfrxethShares = _sfrxethStrategy.shares((address(tokenStakingNode)));

        bool _queuedEverything;

        // 1st queue withdrawals -- steth
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "testQueueWithdrawal: E0");
            (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) = withdrawalsProcessor.getQueueWithdrawalsArgs();
            vm.prank(owner);
            _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

            assertFalse(_queuedEverything, "testQueueWithdrawal: E1");
            assertEq(tokenStakingNode.queuedShares(_stethStrategy), _stethShares, "testQueueWithdrawal: E2");
            assertEq(withdrawalsProcessor.batch(0), 1, "testQueueWithdrawal: E3");

            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(0);
            assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "testQueueWithdrawal: E4");
            assertEq(address(_queuedWithdrawal.strategy), address(_stethStrategy), "testQueueWithdrawal: E5");
            assertEq(_queuedWithdrawal.nonce, 0, "testQueueWithdrawal: E6");
            assertEq(_queuedWithdrawal.shares, _stethShares, "testQueueWithdrawal: E7");
            assertEq(_queuedWithdrawal.startBlock, block.number, "testQueueWithdrawal: E8");
            assertEq(_queuedWithdrawal.completed, false, "testQueueWithdrawal: E9");
        }

        // 2st queue withdrawals -- oeth
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "testQueueWithdrawal: E10");
            (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) = withdrawalsProcessor.getQueueWithdrawalsArgs();
            vm.prank(owner);
            _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

            assertFalse(_queuedEverything, "testQueueWithdrawal: E11");
            assertEq(tokenStakingNode.queuedShares(_oethStrategy), _oethShares, "testQueueWithdrawal: E12");
            assertEq(withdrawalsProcessor.batch(1), 2, "testQueueWithdrawal: E13");

            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(1);
            assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "testQueueWithdrawal: E14");
            assertEq(address(_queuedWithdrawal.strategy), address(_oethStrategy), "testQueueWithdrawal: E15");
            assertEq(_queuedWithdrawal.nonce, 1, "testQueueWithdrawal: E16");
            assertEq(_queuedWithdrawal.shares, _oethShares, "testQueueWithdrawal: E17");
            assertEq(_queuedWithdrawal.startBlock, block.number, "testQueueWithdrawal: E18");
            assertEq(_queuedWithdrawal.completed, false, "testQueueWithdrawal: E19");
        }

        // 3st queue withdrawals -- sfrxeth
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "testQueueWithdrawal: E20");
            (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares) = withdrawalsProcessor.getQueueWithdrawalsArgs();
            vm.prank(owner);
            _queuedEverything = withdrawalsProcessor.queueWithdrawals(_asset, _nodes, _shares);

            assertTrue(_queuedEverything, "testQueueWithdrawal: E21");
            assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), _sfrxethShares, "testQueueWithdrawal: E22");
            assertEq(withdrawalsProcessor.batch(2), 3, "testQueueWithdrawal: E23");

            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(2);
            assertEq(address(_queuedWithdrawal.node), address(tokenStakingNode), "testQueueWithdrawal: E24");
            assertEq(address(_queuedWithdrawal.strategy), address(_sfrxethStrategy), "testQueueWithdrawal: E25");
            assertEq(_queuedWithdrawal.nonce, 2, "testQueueWithdrawal: E26");
            assertEq(_queuedWithdrawal.shares, _sfrxethShares, "testQueueWithdrawal: E27");
            assertEq(_queuedWithdrawal.startBlock, block.number, "testQueueWithdrawal: E28");
            assertEq(_queuedWithdrawal.completed, false, "testQueueWithdrawal: E29");
        }

        // none
        {
            WithdrawalsProcessor.QueuedWithdrawal memory _queuedWithdrawal =
                IWithdrawalsProcessor(address(withdrawalsProcessor)).queuedWithdrawals(3);
            assertEq(address(_queuedWithdrawal.node), address(0), "testQueueWithdrawal: E25");
            assertEq(address(_queuedWithdrawal.strategy), address(0), "testQueueWithdrawal: E26");
            assertEq(_queuedWithdrawal.nonce, 0, "testQueueWithdrawal: E27");
            assertEq(_queuedWithdrawal.shares, 0, "testQueueWithdrawal: E28");
            assertEq(_queuedWithdrawal.startBlock, 0, "testQueueWithdrawal: E29");
            assertEq(_queuedWithdrawal.completed, false, "testQueueWithdrawal: E30");
        }

        assertEq(withdrawalsProcessor.totalQueuedWithdrawals(), withdrawalQueueManager.pendingRequestedRedemptionAmount(), "testQueueWithdrawal: E31");
    }

    //
    // completeQueuedWithdrawals
    //

    function testCompleteQueuedWithdrawals(uint256 _amount) public {
        testQueueWithdrawal(_amount);

        // skip withdrawal delay
        {
            assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testCompleteQueuedWithdrawals: E0");

            IStrategy[] memory _strategies = new IStrategy[](3);
            _strategies[0] = _stethStrategy;
            _strategies[1] = _oethStrategy;
            _strategies[2] = _sfrxethStrategy;
            vm.roll(block.number + eigenLayer.delegationManager.getWithdrawalDelay(_strategies));
        }
        
        // complete queued withdrawals -- steth
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testCompleteQueuedWithdrawals: E1");

            vm.prank(owner);
            withdrawalsProcessor.completeQueuedWithdrawals();

            assertEq(tokenStakingNode.queuedShares(_stethStrategy), 0, "testCompleteQueuedWithdrawals: E2");
            assertEq(withdrawalsProcessor.completedId(), 1, "testCompleteQueuedWithdrawals: E3");
        }

        // complete queued withdrawals -- oeth
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testCompleteQueuedWithdrawals: E4");

            vm.prank(owner);
            withdrawalsProcessor.completeQueuedWithdrawals();

            assertEq(tokenStakingNode.queuedShares(_oethStrategy), 0, "testCompleteQueuedWithdrawals: E5");
            assertEq(withdrawalsProcessor.completedId(), 2, "testCompleteQueuedWithdrawals: E6");
        }

        // complete queued withdrawals -- sfrxeth
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testCompleteQueuedWithdrawals: E7");

            vm.prank(owner);
            withdrawalsProcessor.completeQueuedWithdrawals();

            assertEq(tokenStakingNode.queuedShares(_sfrxethStrategy), 0, "testCompleteQueuedWithdrawals: E8");
            assertEq(withdrawalsProcessor.completedId(), 3, "testCompleteQueuedWithdrawals: E9");
        }

        assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testCompleteQueuedWithdrawals: E10");
    }

    //
    // processPrincipalWithdrawals -- @todo - here
    //

    //
    // internal helpers
    //

    // (1) create token staking node
    // (2) user deposit
    // (3) stake assets to node
    // (4) user request withdrawal
    function setup_(uint256 _amount) private {
        vm.assume(
            _amount > 1 ether &&
            _amount < 100 ether
        );

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