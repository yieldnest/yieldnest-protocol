// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";
import {IWithdrawalsProcessor} from "../../../src/interfaces/IWithdrawalsProcessor.sol";

import {WithdrawalsProcessor} from "../../../src/ynEIGEN/WithdrawalsProcessor.sol";

import "./ynLSDeScenarioBaseTest.sol";

contract WithdrawalsProcessorForkTest is ynLSDeScenarioBaseTest {

    uint256 tokenId;

    bool private _setup = true;

    IWithdrawalsProcessor public withdrawalsProcessor;

    IStrategy private _stethStrategy;
    IStrategy private _oethStrategy;
    IStrategy private _sfrxethStrategy;

    address public constant user = address(0x42069);
    address public constant owner = address(0x42069420);
    address public  keeper;

    function setUp() public virtual override {
        super.setUp();

        // deal assets to user
        {
            deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether});
        }

        keeper = actors.ops.YNEIGEN_WITHDRAWAL_MANAGER;
        withdrawalsProcessor = IWithdrawalsProcessor(chainAddresses.ynEigen.WITHDRAWALS_PROCESSOR_ADDRESS);

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

    function testSatisfyAllWithdrawals() public {
        if (_isOngoingWithdrawals()) return;

        uint256 _amount = 10 ether;
        if (_setup) setup_(_amount);

        // queue withdrawals until `shouldQueueWithdrawals() == false`
        {
            assertTrue(withdrawalsProcessor.shouldQueueWithdrawals(), "testSatisfyAllWithdrawals: E0");

            while (withdrawalsProcessor.shouldQueueWithdrawals()) {
                IWithdrawalsProcessor.QueueWithdrawalsArgs memory _args = withdrawalsProcessor.getQueueWithdrawalsArgs();
                vm.prank(keeper);
                withdrawalsProcessor.queueWithdrawals(_args);
            }

            assertFalse(withdrawalsProcessor.shouldQueueWithdrawals(), "testSatisfyAllWithdrawals: E1");
            assertApproxEqAbs(
                withdrawalsProcessor.getTotalQueuedWithdrawals() + redemptionAssetsVault.availableRedemptionAssets(),
                withdrawalQueueManager.pendingRequestedRedemptionAmount(),
                1e4,
                "testSatisfyAllWithdrawals: E2"
            );
        }

        // skip withdrawal delay
        {
            assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testSatisfyAllWithdrawals: E3");
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
        }

        // complete withdrawals until `shouldCompleteQueuedWithdrawals() == false`
        {
            assertTrue(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testSatisfyAllWithdrawals: E4");
            assertTrue(_isOngoingWithdrawals(), "testSatisfyAllWithdrawals: E5");

            while (withdrawalsProcessor.shouldCompleteQueuedWithdrawals()) {
                vm.prank(keeper);
                withdrawalsProcessor.completeQueuedWithdrawals();
            }

            assertFalse(withdrawalsProcessor.shouldCompleteQueuedWithdrawals(), "testSatisfyAllWithdrawals: E6");
            assertFalse(_isOngoingWithdrawals(), "testSatisfyAllWithdrawals: E7");
        }

        // process principal withdrawals until `shouldProcessPrincipalWithdrawals() == false`
        {
            assertTrue(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "testSatisfyAllWithdrawals: E8");

            while (withdrawalsProcessor.shouldProcessPrincipalWithdrawals()) {
                vm.prank(keeper);
                withdrawalsProcessor.processPrincipalWithdrawals();
            }

            assertFalse(withdrawalsProcessor.shouldProcessPrincipalWithdrawals(), "testSatisfyAllWithdrawals: E9");
            assertApproxEqAbs(withdrawalsProcessor.getTotalQueuedWithdrawals(), 0, 100, "testSatisfyAllWithdrawals: E10");
            assertApproxEqAbs(
                redemptionAssetsVault.availableRedemptionAssets(),
                withdrawalQueueManager.pendingRequestedRedemptionAmount(),
                0.01 ether,
                "testSatisfyAllWithdrawals: E11"
            );
        }

        // make sure nodes balances are roughly the same
        {
            ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
            uint256 _stethStrategyShares = _stethStrategy.shares(address(_nodes[0]));
            uint256 _oethStrategyShares;
            if (!_isHolesky()) _oethStrategyShares = _oethStrategy.shares(address(_nodes[0]));
            uint256 _sfrxethStrategyShares = _sfrxethStrategy.shares(address(_nodes[0]));
            for (uint256 i = 0; i < _nodes.length; i++) {
                assertApproxEqAbs(
                    _stethStrategy.shares(address(_nodes[i])),
                    _stethStrategyShares,
                    100,
                    "testSatisfyAllWithdrawals: E12"
                );
                if (!_isHolesky()) {
                    assertApproxEqAbs(
                        _oethStrategy.shares(address(_nodes[i])), _oethStrategyShares, 1e4, "testSatisfyAllWithdrawals: E13"
                    );
                }
                assertApproxEqAbs(
                    _sfrxethStrategy.shares(address(_nodes[i])),
                    _sfrxethStrategyShares,
                    100,
                    "testSatisfyAllWithdrawals: E14"
                );
            }
        }
    }

    //
    // private helpers
    //

    // (1) user request withdrawal
    function setup_(
        uint256 _amount
    ) private {
        vm.assume(_amount > 1 ether && _amount < 100 ether);

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
                _assetsToDeposit[i].approve(address(yneigen), _amounts[i]);
                yneigen.deposit(_assetsToDeposit[i], _amounts[i], user);
            }
            vm.stopPrank();
        }

        // stake assets equaly to all nodes
        {
            ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();

            _amounts[0] = _amount / _nodes.length;
            _amounts[1] = _amount / _nodes.length;
            if (!_isHolesky()) _amounts[2] = _amount / _nodes.length;

            for (uint256 i = 0; i < _nodes.length; i++) {
                vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
                eigenStrategyManager.stakeAssetsToNode(_nodes[i].nodeId(), _assetsToDeposit, _amounts);
                vm.stopPrank();
            }
        }

        // request withdrawl
        {
            uint256 _balance = yneigen.balanceOf(user);
            vm.startPrank(user);
            yneigen.approve(address(withdrawalQueueManager), _balance);
            tokenId = withdrawalQueueManager.requestWithdrawal(_balance);
            vm.stopPrank();
        }
    }

    function _isOngoingWithdrawals() private returns (bool) {
        IERC20[] memory _assets = assetRegistry.getAssets();
        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < _assets.length; ++i) {
            for (uint256 j = 0; j < _nodes.length; ++j) {
                if (_isHolesky() && _assets[i] == IERC20(chainAddresses.lsd.WOETH_ADDRESS)) continue;
                if (_nodes[j].queuedShares(eigenStrategyManager.strategies(_assets[i])) > 0) return true;
            }
        }
        return false;
    }

}
