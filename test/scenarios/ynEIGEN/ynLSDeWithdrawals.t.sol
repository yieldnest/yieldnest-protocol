// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";

import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";

import "./ynLSDeScenarioBaseTest.sol";
import "forge-std/console.sol";

contract ynLSDeWithdrawalsTest is ynLSDeScenarioBaseTest {

    bool private _setup = true;

    address public constant user = address(0x42069);

    ITokenStakingNode public tokenStakingNode;

    uint256 public constant AMOUNT = 10 ether;

    function setUp() public virtual override {

        super.setUp();

        // deal assets to user
        {
            deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether });
            deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether });
            deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether });
        }

        {
            // Get pending redemption amount
            uint256 pendingAmount = withdrawalQueueManager.pendingRequestedRedemptionAmount() + 100 wei;
            
            // Convert pendingAmount from stETH to wstETH
            uint256 pendingAmountInWstETH = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS).getWstETHByStETH(pendingAmount);
            // Top up vault with wstETH
            address topper = address(0x421337);
            
            // Get stETH and wrap to wstETH
            deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: topper, give: pendingAmountInWstETH});
            
            vm.startPrank(topper);
            // Deposit wstETH to redemption vault
            IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(redemptionAssetsVault), pendingAmountInWstETH);
            redemptionAssetsVault.deposit(pendingAmountInWstETH, chainAddresses.lsd.WSTETH_ADDRESS);
            vm.stopPrank();
        }

        // top up redemptionAssetsVault
        {
            address _topper = address(0x420420);
            uint256 _amount = 50; // 50 wei
            deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: _topper, give: _amount });
            deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: _topper, give: _amount });
            deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: _topper, give: _amount });
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

    //
    // queueWithdrawals
    //

    function testQueueWithdrawalSTETH() public {
        _queueWithdrawalSTETH(AMOUNT);
    }

    function testQueueWithdrawalSFRXETH() public {
        _queueWithdrawalSFRXETH(AMOUNT);
    }

    function testQueueWithdrawalOETH() public {
        vm.skip(_isHolesky());
        _queueWithdrawalOETH(AMOUNT);
    }

    function testQueueWithdrawalsWrongCaller() public {
        _queueWithdrawalsWrongCaller();
    }

    //
    // completeQueuedWithdrawals
    //

    function testCompleteQueuedWithdrawalsSTETH() public {
        _completeQueuedWithdrawalsSTETH(AMOUNT);
    }

    function testCompleteQueuedWithdrawalsSFRXETH() public {
        _completeQueuedWithdrawalsSFRXETH(AMOUNT);
    }
    

    function testCompleteQueuedWithdrawalsOETH() public {
        vm.skip(_isHolesky());
        _completeQueuedWithdrawalsOETH(AMOUNT);
    }

    function testCompleteAllWithdrawals() public {
       _completeAllWithdrawals(AMOUNT);
    }

    //
    // processPrincipalWithdrawals
    //

    function testProcessPrincipalWithdrawals() public {
        _processPrincipalWithdrawals(AMOUNT);
    }

    function testProcessPrincipalWithdrawalsNoReinvest() public {
        _processPrincipalWithdrawalsNoReinvest(AMOUNT);
    }

    //
    // requestWithdrawal
    //

    function testRequestWithdrawal() public returns (uint256) {
        return _requestWithdrawal(AMOUNT);
    }

    //
    // claimWithdrawal
    //

    function testClaimWithdrawalFixed() public {
        _claimWithdrawalFixed(AMOUNT);
    }
    


    //
    // internal helpers
    //

    function _queueWithdrawalSTETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        uint256 _shares = _strategy.shares((address(tokenStakingNode)));

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.queueWithdrawals(_strategy, _shares);

        assertEq(yneigen.totalAssets(), _totalAssetsBefore, "queueWithdrawalSTETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), _shares, "queueWithdrawalSTETH: E1");
    }

    function _queueWithdrawalSFRXETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
        uint256 _shares = _strategy.shares((address(tokenStakingNode)));

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.queueWithdrawals(_strategy, _shares);

        assertEq(yneigen.totalAssets(), _totalAssetsBefore, "queueWithdrawalSFRXETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), _shares, "queueWithdrawalSFRXETH: E1");
    }

    function _queueWithdrawalOETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);
        uint256 _shares = _strategy.shares((address(tokenStakingNode)));

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.queueWithdrawals(_strategy, _shares);

        assertEq(yneigen.totalAssets(), _totalAssetsBefore, "queueWithdrawalOETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), _shares, "queueWithdrawalOETH: E1");
    }

    function _queueWithdrawalsWrongCaller() internal {
        _setupTokenStakingNode(AMOUNT);

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
        uint256 _shares = _strategy.shares((address(tokenStakingNode)));

        vm.expectRevert(abi.encodeWithSelector(TokenStakingNode.NotTokenStakingNodesWithdrawer.selector));
        tokenStakingNode.queueWithdrawals(_strategy, _shares);
    }

    function _completeQueuedWithdrawalsSTETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        _setup = false;
        _queueWithdrawalSTETH(_amount);

        uint256 _nonce = delegationManager.cumulativeWithdrawalsQueued(address(tokenStakingNode)) - 1;
        uint32 _startBlock = uint32(block.number);
        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        uint256 _shares = tokenStakingNode.queuedShares(_strategy);
        uint256[] memory _middlewareTimesIndexes = new uint256[](1);
        _middlewareTimesIndexes[0] = 0;

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = _strategy;
        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.completeQueuedWithdrawals(_nonce, _startBlock, _shares, _strategy, _middlewareTimesIndexes, true);

        assertApproxEqAbs(yneigen.totalAssets(), _totalAssetsBefore, 10, "completeQueuedWithdrawalsSTETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), 0, "completeQueuedWithdrawalsSTETH: E1");
        assertApproxEqAbs(tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WSTETH_ADDRESS)), _amount, 100, "completeQueuedWithdrawalsSTETH: E2");
    }

    function _completeQueuedWithdrawalsSFRXETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        _setup = false;
        _queueWithdrawalSFRXETH(_amount);

        uint256 _nonce = delegationManager.cumulativeWithdrawalsQueued(address(tokenStakingNode)) - 1;
        uint32 _startBlock = uint32(block.number);
        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
        uint256 _shares = tokenStakingNode.queuedShares(_strategy);
        uint256[] memory _middlewareTimesIndexes = new uint256[](1);
        _middlewareTimesIndexes[0] = 0;

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = _strategy;
        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.completeQueuedWithdrawals(_nonce, _startBlock, _shares, _strategy, _middlewareTimesIndexes, true);

        assertApproxEqAbs(yneigen.totalAssets(), _totalAssetsBefore, 10, "ompleteQueuedWithdrawalsSFRXETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), 0, "completeQueuedWithdrawalsSFRXETH: E1");
        assertApproxEqAbs(tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS)), _amount, 100, "completeQueuedWithdrawalsSFRXETH: E2");
    }

    function _completeQueuedWithdrawalsOETH(uint256 _amount) internal {
        if (_setup) _setupTokenStakingNode(_amount);

        _setup = false;
        _queueWithdrawalOETH(_amount);

        uint256 _nonce = delegationManager.cumulativeWithdrawalsQueued(address(tokenStakingNode)) - 1;
        uint32 _startBlock = uint32(block.number);
        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);
        uint256 _shares = tokenStakingNode.queuedShares(_strategy);
        uint256[] memory _middlewareTimesIndexes = new uint256[](1);
        _middlewareTimesIndexes[0] = 0;

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = _strategy;
        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.completeQueuedWithdrawals(_nonce, _startBlock, _shares, _strategy, _middlewareTimesIndexes, true);

        assertApproxEqAbs(yneigen.totalAssets(), _totalAssetsBefore, 10, "completeQueuedWithdrawalsOETH: E0");
        assertEq(tokenStakingNode.queuedShares(_strategy), 0, "completeQueuedWithdrawalsOETH: E1");
        assertApproxEqAbs(tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WOETH_ADDRESS)), _amount, 100, "completeQueuedWithdrawalsOETH: E2");
    }

    function _completeAllWithdrawals(uint256 _amount) internal {
       _setupTokenStakingNode(_amount);

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        _setup = false;
        _completeQueuedWithdrawalsSTETH(_amount);
        _completeQueuedWithdrawalsSFRXETH(_amount);
        if (!_isHolesky()) _completeQueuedWithdrawalsOETH(_amount);

        assertApproxEqAbs(yneigen.totalAssets(), _totalAssetsBefore, 10, "completeAllWithdrawals: E0");
    }

    function _processPrincipalWithdrawals(uint256 _amount) internal {
        _completeAllWithdrawals(_amount);

        uint256 _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));
        uint256 _length = _isHolesky() ? 2 : 3;

        IYieldNestStrategyManager.WithdrawalAction[] memory _actions = new IYieldNestStrategyManager.WithdrawalAction[](_length);
        _actions[0] = IYieldNestStrategyManager.WithdrawalAction({
            nodeId: tokenStakingNode.nodeId(),
            amountToReinvest: _availableToWithdraw / 2,
            amountToQueue: _availableToWithdraw / 2,
            asset: chainAddresses.lsd.WSTETH_ADDRESS
        });
        _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS));
        _actions[1] = IYieldNestStrategyManager.WithdrawalAction({
            nodeId: tokenStakingNode.nodeId(),
            amountToReinvest: _availableToWithdraw / 2,
            amountToQueue: _availableToWithdraw / 2,
            asset: chainAddresses.lsd.SFRXETH_ADDRESS
        });
        if (!_isHolesky()) {
            _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WOETH_ADDRESS));
            _actions[1] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: tokenStakingNode.nodeId(),
                amountToReinvest: _availableToWithdraw / 2,
                amountToQueue: _availableToWithdraw / 2,
                asset: chainAddresses.lsd.WOETH_ADDRESS
            });
        }

        uint256 _totalAssetsBefore = yneigen.totalAssets();
        uint256 _ynEigenWSTETHBalanceBefore = yneigen.assets(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 _ynEigenSFRXETHBalanceBefore = yneigen.assets(chainAddresses.lsd.SFRXETH_ADDRESS);
        uint256 _redemptionVaultWSTETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 _redemptionVaultSFRXETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.SFRXETH_ADDRESS);

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        eigenStrategyManager.processPrincipalWithdrawals(_actions);

        assertEq(yneigen.totalAssets(), _totalAssetsBefore, "processPrincipalWithdrawals: E0");
        assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.WSTETH_ADDRESS) - _redemptionVaultWSTETHBalanceBefore, _availableToWithdraw / 2, 50, "processPrincipalWithdrawals: E1");
        assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.SFRXETH_ADDRESS) - _redemptionVaultSFRXETHBalanceBefore, _availableToWithdraw / 2, 50, "processPrincipalWithdrawals: E3");
        assertApproxEqAbs(yneigen.assets(chainAddresses.lsd.WSTETH_ADDRESS), _ynEigenWSTETHBalanceBefore + _availableToWithdraw / 2, 2, "processPrincipalWithdrawals: E4");
        assertEq(yneigen.assets(chainAddresses.lsd.SFRXETH_ADDRESS), _ynEigenSFRXETHBalanceBefore + _availableToWithdraw / 2, "processPrincipalWithdrawals: E6");

        if (!_isHolesky()) {
            uint256 _ynEigenWOETHBalanceBefore = yneigen.assets(chainAddresses.lsd.WOETH_ADDRESS);
            uint256 _redemptionVaultWOETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.WOETH_ADDRESS);
            assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.WOETH_ADDRESS) - _redemptionVaultWOETHBalanceBefore, _availableToWithdraw / 2, 50, "processPrincipalWithdrawals: E2");
            assertApproxEqAbs(yneigen.assets(chainAddresses.lsd.WOETH_ADDRESS), _ynEigenWOETHBalanceBefore + _availableToWithdraw / 2, 2, "processPrincipalWithdrawals: E5");
        }
    }

    function _processPrincipalWithdrawalsNoReinvest(uint256 _amount) internal {
        _completeAllWithdrawals(_amount);

        uint256 _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));
        
        uint256 _len = _isHolesky() ? 2 : 3;

        IYieldNestStrategyManager.WithdrawalAction[] memory _actions = new IYieldNestStrategyManager.WithdrawalAction[](_len);
        _actions[0] = IYieldNestStrategyManager.WithdrawalAction({
            nodeId: tokenStakingNode.nodeId(),
            amountToReinvest: 0,
            amountToQueue: _availableToWithdraw,
            asset: chainAddresses.lsd.WSTETH_ADDRESS
        });
        _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS));
        _actions[1] = IYieldNestStrategyManager.WithdrawalAction({
            nodeId: tokenStakingNode.nodeId(),
            amountToReinvest: 0,
            amountToQueue: _availableToWithdraw,
            asset: chainAddresses.lsd.SFRXETH_ADDRESS
        });
        if (!_isHolesky()) {
            _availableToWithdraw = tokenStakingNode.withdrawn(IERC20(chainAddresses.lsd.WOETH_ADDRESS));
            _actions[2] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: tokenStakingNode.nodeId(),
                amountToReinvest: 0,
                amountToQueue: _availableToWithdraw,
                asset: chainAddresses.lsd.WOETH_ADDRESS
            });
        }

        uint256 _totalAssetsBefore = yneigen.totalAssets();
        uint256 _ynEigenWSTETHBalanceBefore = yneigen.assets(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 _ynEigenSFRXETHBalanceBefore = yneigen.assets(chainAddresses.lsd.SFRXETH_ADDRESS);

        {
            uint256 _redemptionVaultWSTETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.WSTETH_ADDRESS);
            uint256 _redemptionVaultSFRXETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.SFRXETH_ADDRESS);

            vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
            eigenStrategyManager.processPrincipalWithdrawals(_actions);

            assertEq(yneigen.totalAssets(), _totalAssetsBefore, "processPrincipalWithdrawalsNoReinvest: E0");
            assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.WSTETH_ADDRESS) - _redemptionVaultWSTETHBalanceBefore, _availableToWithdraw, 50, "processPrincipalWithdrawalsNoReinvest: E1");
            assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.SFRXETH_ADDRESS) - _redemptionVaultSFRXETHBalanceBefore, _availableToWithdraw, 50, "processPrincipalWithdrawalsNoReinvest: E3");
        }   

        assertEq(yneigen.assets(chainAddresses.lsd.WSTETH_ADDRESS), _ynEigenWSTETHBalanceBefore, "processPrincipalWithdrawalsNoReinvest: E4");
        assertEq(yneigen.assets(chainAddresses.lsd.SFRXETH_ADDRESS), _ynEigenSFRXETHBalanceBefore, "processPrincipalWithdrawalsNoReinvest: E6");

        if (!_isHolesky()) {
            uint256 _ynEigenWOETHBalanceBefore = yneigen.assets(chainAddresses.lsd.WOETH_ADDRESS);
            uint256 _redemptionVaultWOETHBalanceBefore = redemptionAssetsVault.balances(chainAddresses.lsd.WOETH_ADDRESS);
            assertApproxEqAbs(redemptionAssetsVault.balances(chainAddresses.lsd.WOETH_ADDRESS) - _redemptionVaultWOETHBalanceBefore, _availableToWithdraw, 50, "processPrincipalWithdrawalsNoReinvest: E2");
            assertEq(yneigen.assets(chainAddresses.lsd.WOETH_ADDRESS), _ynEigenWOETHBalanceBefore, "processPrincipalWithdrawalsNoReinvest: E5");
        }
    }

    function _requestWithdrawal(uint256 _amount) internal returns (uint256) {
        _processPrincipalWithdrawalsNoReinvest(_amount);

        uint256 _totalAssetsBefore = yneigen.totalAssets();

        uint256 _userYnLSDeBalance = yneigen.balanceOf(user);
        vm.startPrank(user);
        yneigen.approve(address(withdrawalQueueManager), _userYnLSDeBalance);
        uint256 expectedTokenId = withdrawalQueueManager._tokenIdCounter();
        uint256 _tokenId = withdrawalQueueManager.requestWithdrawal(_userYnLSDeBalance);
        vm.stopPrank();

        assertEq(_tokenId, expectedTokenId, "requestWithdrawal: E1");
        assertEq(_totalAssetsBefore, yneigen.totalAssets(), "requestWithdrawal: E2");

        return _tokenId;
    }

    function _claimWithdrawalFixed(uint256 _amount) internal {
        uint256 tokenId = _requestWithdrawal(_amount);

        vm.prank(actors.ops.YNEIGEN_REQUEST_FINALIZER);
        withdrawalQueueManager.finalizeRequestsUpToIndex(tokenId + 1);

        uint256 _userWSTETHBalanceBefore = IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user);
        uint256 _userWOETHBalanceBefore = IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user);
        uint256 _userSFRXETHBalanceBefore = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user);
        uint256 _totalAssetsBefore = yneigen.totalAssets();
        uint256 _redemptionRateBefore = redemptionAssetsVault.redemptionRate();

        IWithdrawalQueueManager.WithdrawalRequest memory request = withdrawalQueueManager.withdrawalRequest(tokenId);

        vm.prank(user);
        withdrawalQueueManager.claimWithdrawal(tokenId, user);

        uint256 totalETHValueReceived;
        {
            uint256 _userWSTETHBalanceDelta = IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user) - _userWSTETHBalanceBefore;
            uint256 _userWOETHBalanceDelta = IERC20(chainAddresses.lsd.WOETH_ADDRESS).balanceOf(user) - _userWOETHBalanceBefore;
            uint256 _userSFRXETHBalanceDelta = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).balanceOf(user) - _userSFRXETHBalanceBefore;

            // Calculate total ETH value received by converting each asset delta to ETH
            totalETHValueReceived = assetRegistry.convertToUnitOfAccount(
                IERC20(chainAddresses.lsd.WSTETH_ADDRESS), 
                _userWSTETHBalanceDelta
            ) + assetRegistry.convertToUnitOfAccount(
                IERC20(chainAddresses.lsd.SFRXETH_ADDRESS),
                _userSFRXETHBalanceDelta
            );

            if (!_isHolesky()) {
                totalETHValueReceived += assetRegistry.convertToUnitOfAccount(
                    IERC20(chainAddresses.lsd.WOETH_ADDRESS),
                    _userWOETHBalanceDelta
                );
            }
        }

        uint256 totalETHValueExpected = withdrawalQueueManager.calculateRedemptionAmount(request.amount, request.redemptionRateAtRequestTime);

        assertApproxEqRel(
            totalETHValueReceived,
            totalETHValueExpected * (1000000 - withdrawalQueueManager.withdrawalFee()) / 1000000,
            1e16, // max 0.01% difference
            "testClaimWithdrawal: total ETH value mismatch"
        );

        assertLt(yneigen.totalAssets(), _totalAssetsBefore, "testClaimWithdrawal: E3");
        assertApproxEqRel(redemptionAssetsVault.redemptionRate(), _redemptionRateBefore, 1, "testClaimWithdrawal: E4");
    }

    function _setupTokenStakingNode(uint256 _amount) private {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        uint256 _len = _isHolesky() ? 2 : 3;
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        _assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        if (!_isHolesky()) {
            _assetsToDeposit[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        }

        uint256[] memory _amounts = new uint256[](_len);
        _amounts[0] = _amount;
        _amounts[1] = _amount;
        if (!_isHolesky()) _amounts[2] = _amount;

        vm.startPrank(user);
        for (uint256 i = 0; i < _len; i++) {
            _assetsToDeposit[i].approve(address(yneigen), _amounts[i]);
            yneigen.deposit(_assetsToDeposit[i], _amounts[i], user);
        }
        vm.stopPrank();

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), _assetsToDeposit, _amounts);
        vm.stopPrank();
    }

    function _isHolesky() private view returns (bool) {
        return block.chainid == 17000;
    }
}