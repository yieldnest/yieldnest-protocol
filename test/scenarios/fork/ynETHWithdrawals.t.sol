// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IWithdrawalQueueManager} from "../../../src/interfaces/IWithdrawalQueueManager.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IRedeemableAsset} from "../../../src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "../../../src/interfaces/IRedemptionAssetsVault.sol";
import {IynETH} from "../../../src/interfaces/IynETH.sol";

import {StakingNode} from "../../../src/StakingNode.sol";
import {WithdrawalQueueManager} from "../../../src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault, ETH_ASSET} from "../../../src/ynETHRedemptionAssetsVault.sol";

import "../../utils/StakingNodeTestBase.sol";

contract ynETHWithdrawals is StakingNodeTestBase {

    error CallerNotOwnerNorApproved(uint256 tokenId, address caller);
    error NotFinalized(uint256 currentTimestamp, uint256 requestTimestamp, uint256 queueDuration);
    error ERC721NonexistentToken(uint256 tokenId);
    error InsufficientBalance(uint256 currentBalance, uint256 requestedBalance);
    error InsufficientAssetBalance(address asset, uint256 requestedAmount, uint256 balance);
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AmountExceedsSurplus(uint256 requestedAmount, uint256 availableSurplus);
    error SecondsToFinalizationExceedsLimit(uint256 value);

    bool public isHolesky;

    address public constant user = address(0x12345678);
    address public constant receiver = address(0x987654321);

    uint256 public nodeId = 2;
    uint256 public withdrawalAmount = 32 ether;

    uint256 tokenId;
    uint256 secondsToFinalization;
    uint256 amountOut;

    StakingNode public stakingNode;

    // ------------------------------------------
    // Setup
    // ------------------------------------------

    function setUp() public override {
        super.setUp();

        isHolesky = block.chainid == 17000;

        if(isHolesky) {
            stakingNode = StakingNode(payable(address(stakingNodesManager.nodes(nodeId))));

            vm.deal(user, 10_000 ether);

            setupForVerifyWithdrawalCredentials(nodeId, "test/data/holesky_wc_proof_1916455.json");

            secondsToFinalization = 1 days;
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setSecondsToFinalization(secondsToFinalization);
        }
    }

    // ------------------------------------------
    // Withdrawal flow tests
    // ------------------------------------------

    function testVerifyWithdrawalCredentials() public {
        if (!isHolesky) return;

        ValidatorProofs memory _validatorProofs = getWithdrawalCredentialParams();

        uint256 _unverifiedStakedETH = stakingNode.unverifiedStakedETH();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNode.verifyWithdrawalCredentials(
            uint64(block.timestamp),
            _validatorProofs.stateRootProof,
            _validatorProofs.validatorIndices,
            _validatorProofs.withdrawalCredentialProofs,
            _validatorProofs.validatorFields
        );

        assertEq(stakingNode.unverifiedStakedETH(), _unverifiedStakedETH, "testVerifyWithdrawalCredentials: E0"); // validator already verified withdrawal credentials
    }

    function testVerifyWithdrawalCredentialsWrongCaller() public {
        if (!isHolesky) return;

        ValidatorProofs memory _validatorProofs = getWithdrawalCredentialParams();

        vm.expectRevert(bytes4(keccak256("NotStakingNodesOperator()")));
        stakingNode.verifyWithdrawalCredentials(
            uint64(block.timestamp),
            _validatorProofs.stateRootProof,
            _validatorProofs.validatorIndices,
            _validatorProofs.withdrawalCredentialProofs,
            _validatorProofs.validatorFields
        );
    }

    function testQueueWithdrawal() public {
        if (!isHolesky) return;

        testVerifyWithdrawalCredentials();

        uint256 _queuedSharesAmountBefore = stakingNode.queuedSharesAmount();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNode.queueWithdrawals(withdrawalAmount);

        assertEq(stakingNode.queuedSharesAmount(), _queuedSharesAmountBefore + withdrawalAmount, "testQueueWithdrawal: E0");

        _queuedSharesAmountBefore = stakingNode.queuedSharesAmount();
        uint256 _balanceBefore = address(stakingNode).balance;
        uint256 _withdrawnValidatorPrincipalBefore = stakingNode.withdrawnValidatorPrincipal();
        completeQueuedWithdrawals(stakingNode, withdrawalAmount);
        assertEq(address(stakingNode).balance - _balanceBefore, withdrawalAmount, "testQueueWithdrawal: E1");
        assertEq(stakingNode.queuedSharesAmount(), _queuedSharesAmountBefore - withdrawalAmount, "testQueueWithdrawal: E2");
        assertEq(stakingNode.withdrawnValidatorPrincipal(), _withdrawnValidatorPrincipalBefore + withdrawalAmount, "testQueueWithdrawal: E3");
    }

    function testQueueWithdrawalWrongCaller() public {
        if (!isHolesky) return;

        vm.expectRevert(bytes4(keccak256("NotStakingNodesOperator()")));
        stakingNode.queueWithdrawals(withdrawalAmount);
    }

    function testRequestWithdrawal(uint256 _amount) public {
        if (!isHolesky) return;

        vm.assume(_amount > 0 && _amount < 10_000 ether);

        testQueueWithdrawal();

        uint256 _expectedTokenAmount = yneth.previewDeposit(_amount);

        {
            vm.prank(user);
            uint256 _actualAmount = yneth.depositETH{value: _amount}(user);
            assertEq(_actualAmount, _expectedTokenAmount, "testRequestWithdrawal: E0");
        }

        uint256 _ynETHBalanceBefore = yneth.balanceOf(user);
        assertGe(_ynETHBalanceBefore, _amount, "testRequestWithdrawal: E1");

        uint256 _expectedAmountOut = yneth.previewRedeem(_expectedTokenAmount);
        uint256 _queueManagerBalanceBefore = yneth.balanceOf(address(ynETHWithdrawalQueueManager));
        uint256 _pendingRequestedRedemptionAmountBefore = ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount();

        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), _expectedTokenAmount);
        tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(_expectedTokenAmount);
        vm.stopPrank();

        amountOut = ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount() - _pendingRequestedRedemptionAmountBefore;

        assertEq(yneth.balanceOf(user), 0, "testRequestWithdrawal: E2");
        assertGt(ynETHWithdrawalQueueManager.balanceOf(user), 0, "testRequestWithdrawal: E3");
        assertEq(ynETHWithdrawalQueueManager.ownerOf(tokenId), user, "testRequestWithdrawal: E4");
        assertEq(yneth.balanceOf(address(ynETHWithdrawalQueueManager)) - _queueManagerBalanceBefore, _expectedTokenAmount, "testRequestWithdrawal: E5");
        assertApproxEqAbs(amountOut, _expectedAmountOut, 100_000, "testRequestWithdrawal: E6");
        assertGe(_expectedAmountOut, amountOut, "testRequestWithdrawal: E7");

        {
            IWithdrawalQueueManager.WithdrawalRequest memory _request = ynETHWithdrawalQueueManager.withdrawalRequest(tokenId);
            assertEq(_request.amount, _expectedTokenAmount, "testRequestWithdrawal: E8");
            assertEq(ynETHWithdrawalQueueManager.withdrawalFee(), _request.feeAtRequestTime, "testRequestWithdrawal: E9");
            assertEq(yneth.previewRedeem(1 ether), _request.redemptionRateAtRequestTime, "testRequestWithdrawal: E10");
            assertEq(_request.creationTimestamp, block.timestamp, "testRequestWithdrawal: E11");
            assertTrue(!_request.processed, "testRequestWithdrawal: E12");
        }
    }

    function testProcessPrincipalWithdrawalsForNode() public {
        if (!isHolesky) return;

        testRequestWithdrawal(withdrawalAmount);

        uint256 _withdrawnValidatorPrincipalBefore = stakingNode.withdrawnValidatorPrincipal();
        uint256 _stakingNodesManagerBalanceBefore = address(stakingNodesManager).balance;
        uint256 _ynETHBalanceBefore = address(yneth).balance;
        uint256 _withdrawalAssetsVaultBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        uint256 _availableRedemptionAssetsBefore = ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets();

        IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
        _actions[0] = IStakingNodesManager.WithdrawalAction({
            nodeId: nodeId,
            amountToReinvest: 0,
            amountToQueue: withdrawalAmount
        });

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        stakingNodesManager.processPrincipalWithdrawals(_actions);

        assertEq(stakingNode.withdrawnValidatorPrincipal() + withdrawalAmount, _withdrawnValidatorPrincipalBefore, "testProcessPrincipalWithdrawalsForNode: E0");
        assertEq(address(stakingNodesManager).balance, _stakingNodesManagerBalanceBefore, "testProcessPrincipalWithdrawalsForNode: E1");
        assertEq(address(yneth).balance, _ynETHBalanceBefore, "testProcessPrincipalWithdrawalsForNode: E2");
        assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _withdrawalAssetsVaultBalanceBefore + withdrawalAmount, "testProcessPrincipalWithdrawalsForNode: E3");
        assertEq(ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(), _availableRedemptionAssetsBefore + withdrawalAmount, "testProcessPrincipalWithdrawalsForNode: E4");
    }

    function testProcessPrincipalWithdrawalsForNodeWrongCaller() public {
        if (!isHolesky) return;

        IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
        _actions[0] = IStakingNodesManager.WithdrawalAction({
            nodeId: nodeId,
            amountToReinvest: 0,
            amountToQueue: withdrawalAmount
        });

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), stakingNodesManager.WITHDRAWAL_MANAGER_ROLE()));
        stakingNodesManager.processPrincipalWithdrawals(_actions);
    }

    function testClaimWithdrawalInsufficientBalance() public {
        if (!isHolesky) return;

        testRequestWithdrawal(withdrawalAmount);

        vm.warp(block.timestamp + ynETHWithdrawalQueueManager.secondsToFinalization());
        if (ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets() < withdrawalAmount) {
            // vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, address(ynETHWithdrawalQueueManager).balance, withdrawalAmount - 40));
            // fails with above error, but `_amount` varies because of little precision loss
            vm.expectRevert();
            vm.prank(user);
            ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);
        }
    }

    function testClaimWithdrawal() public {
        if (!isHolesky) return;

        testProcessPrincipalWithdrawalsForNode();

        vm.warp(block.timestamp + ynETHWithdrawalQueueManager.secondsToFinalization());

        uint256 _pendingRequestedRedemptionAmountBefore = ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 _totalSupplyBefore = yneth.totalSupply();
        uint256 _receiverBalanceBefore = address(receiver).balance;
        uint256 _feeReceiverBalanceBefore = address(ynETHWithdrawalQueueManager.feeReceiver()).balance;

        vm.prank(user);
        uint256[] memory _tokenIds = new uint256[](1);
        address[] memory _receivers = new address[](1);
        _tokenIds[0] = tokenId;
        _receivers[0] = receiver;
        ynETHWithdrawalQueueManager.claimWithdrawals(_tokenIds, _receivers);

        vm.expectRevert(abi.encodeWithSelector(ERC721NonexistentToken.selector, tokenId));
        ynETHWithdrawalQueueManager.ownerOf(tokenId);

        (uint256 _reqAmount, uint256 _feeAtRequestTime,,, bool _processed) = ynETHWithdrawalQueueManager.withdrawalRequests(tokenId);
        assertTrue(_processed, "testClaimWithdrawal: E0");

        uint256 _feeAmount = ynETHWithdrawalQueueManager.calculateFee(amountOut, _feeAtRequestTime);
        uint256 _receiverAmount = amountOut - _feeAmount;

        assertEq(ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount(), _pendingRequestedRedemptionAmountBefore - amountOut, "testClaimwithdrawal: E1");
        assertEq(yneth.totalSupply(), _totalSupplyBefore - _reqAmount, "testClaimwithdrawal: E2");
        assertEq(address(receiver).balance - _receiverBalanceBefore, _receiverAmount, "testClaimwithdrawal: E3");
        assertEq(address(ynETHWithdrawalQueueManager.feeReceiver()).balance - _feeReceiverBalanceBefore, _feeAmount, "testClaimwithdrawal: E4");
    }

    function testClaimWithdrawalWrongCaller() public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(CallerNotOwnerNorApproved.selector, tokenId, address(this)));
        ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);
    }

    function testClaimWithdrawalNotFinalized() public {
        if (!isHolesky) return;

        testProcessPrincipalWithdrawalsForNode();

        vm.expectRevert(abi.encodeWithSelector(NotFinalized.selector, block.timestamp, block.timestamp, secondsToFinalization));
        vm.prank(user);
        ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);
    }

    // ------------------------------------------
    // Unit tests - WithdrawalQueueManager
    // ------------------------------------------

    function testInitializationManager() public {
        if (!isHolesky) return;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(new WithdrawalQueueManager()),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        WithdrawalQueueManager _manager = WithdrawalQueueManager(address(_proxy));

        string memory _name = "ynETH Withdrawal Manager";
        string memory _symbol = "ynETHWM";
        address _redeemableAsset = address(yneth);
        address _redemptionAssetsVault = address(ynETHRedemptionAssetsVaultInstance);
        address _admin = actors.admin.PROXY_ADMIN_OWNER;
        address _withdrawalQueueAdmin = actors.ops.WITHDRAWAL_MANAGER;
        uint256 _withdrawalFee = 500;
        address _feeReceiver = actors.admin.FEE_RECEIVER;
        WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
            name: _name,
            symbol: _symbol,
            redeemableAsset: IRedeemableAsset(_redeemableAsset),
            redemptionAssetsVault: IRedemptionAssetsVault(_redemptionAssetsVault),
            admin: _admin,
            withdrawalQueueAdmin: _withdrawalQueueAdmin,
            redemptionAssetWithdrawer: _withdrawalQueueAdmin,
            withdrawalFee: _withdrawalFee,
            feeReceiver: _feeReceiver
        });
        _manager.initialize(_init);

        assertEq(_manager.name(), _name, "testInitialization: E0");
        assertEq(_manager.symbol(), _symbol, "testInitialization: E1");
        assertEq(address(_manager.redeemableAsset()), _redeemableAsset, "testInitialization: E2");
        assertEq(address(_manager.redemptionAssetsVault()), _redemptionAssetsVault, "testInitialization: E3");
        assertEq(_manager.withdrawalFee(), _withdrawalFee, "testInitialization: E4");
        assertEq(address(_manager.feeReceiver()), _feeReceiver, "testInitialization: E5");
        assertEq(_manager.hasRole(_manager.DEFAULT_ADMIN_ROLE(), _admin), true, "testInitialization: E6");
        assertEq(_manager.hasRole(_manager.WITHDRAWAL_QUEUE_ADMIN_ROLE(), _withdrawalQueueAdmin), true, "testInitialization: E7");
    }

    function testInitializationManagerInvalid() public {
        if (!isHolesky) return;

        string memory _name = "ynETH Withdrawal Manager";
        string memory _symbol = "ynETHWM";
        address _redeemableAsset = address(yneth);
        address _redemptionAssetsVault = address(ynETHRedemptionAssetsVaultInstance);
        address _admin = actors.admin.PROXY_ADMIN_OWNER;
        address _withdrawalQueueAdmin = actors.ops.WITHDRAWAL_MANAGER;
        uint256 _withdrawalFee = 500;
        address _feeReceiver = actors.admin.FEE_RECEIVER;
        WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
            name: _name,
            symbol: _symbol,
            redeemableAsset: IRedeemableAsset(_redeemableAsset),
            redemptionAssetsVault: IRedemptionAssetsVault(_redemptionAssetsVault),
            admin: _admin,
            withdrawalQueueAdmin: _withdrawalQueueAdmin,
            redemptionAssetWithdrawer: _withdrawalQueueAdmin,
            withdrawalFee: _withdrawalFee,
            feeReceiver: _feeReceiver
        });

        vm.expectRevert(bytes4(keccak256("InvalidInitialization()")));
        ynETHWithdrawalQueueManager.initialize(_init);
    }

    function testSetSecondsToFinalization(uint256 _secondsToFinalization) public {
        if (!isHolesky) return;

        vm.assume(_secondsToFinalization < ynETHWithdrawalQueueManager.MAX_SECONDS_TO_FINALIZATION());

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        ynETHWithdrawalQueueManager.setSecondsToFinalization(_secondsToFinalization);
        assertEq(ynETHWithdrawalQueueManager.secondsToFinalization(), _secondsToFinalization, "testSetSecondsToFinalization: E0");
    }

    function testSetSecondsToFinalizationWrongCaller(uint256 _secondsToFinalization) public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setSecondsToFinalization(_secondsToFinalization);
    }

    function testSetSecondsToFinalizationSecondsToFinalizationExceedsLimit(uint256 _secondsToFinalization) public {
        if (!isHolesky) return;

        uint256 _secondsToFinalization = ynETHWithdrawalQueueManager.MAX_SECONDS_TO_FINALIZATION() + 1;

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(SecondsToFinalizationExceedsLimit.selector, _secondsToFinalization));
        ynETHWithdrawalQueueManager.setSecondsToFinalization(_secondsToFinalization);
    }

    function testSetWithdrawalFee(uint256 _feePercentage) public {
        if (!isHolesky) return;

        if (_feePercentage <= ynETHWithdrawalQueueManager.FEE_PRECISION()) {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);
            assertEq(ynETHWithdrawalQueueManager.withdrawalFee(), _feePercentage, "testSetWithdrawalFee: E0");
        }
    }

    function testSetWithdrawalFeeWrongCaller(uint256 _feePercentage) public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);
    }

    function testSetWithdrawalFeeWrongPercentage(uint256 _feePercentage) public {
        if (!isHolesky) return;

        if (_feePercentage > ynETHWithdrawalQueueManager.FEE_PRECISION()) {
            vm.expectRevert(bytes4(keccak256("FeePercentageExceedsLimit()")));
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);
        }
    }

    function testFeeReceiver(address _feeReceiver) public {
        if (!isHolesky) return;

        if (_feeReceiver != address(0)) {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);
            assertEq(ynETHWithdrawalQueueManager.feeReceiver(), _feeReceiver, "testFeeReceiver: E0");
        }
    }

    function testFeeReceiverWrongCaller(address _feeReceiver) public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);
    }

    function testFeeReceiverZeroAddress() public {
        if (!isHolesky) return;

        address _feeReceiver = address(0);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);
    }

    function testSurplusRedemptionAssets() public {
        if (!isHolesky) return;

        uint256 _balanceOfVaultBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _balanceOfVaultBefore - ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount(), "testSurplusRedemptionAssets: E0");

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), 1 ether);
        assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _balanceOfVaultBefore - ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount() + 1 ether, "testSurplusRedemptionAssets: E1");
    }

    function testDeficitRedemptionAssets() public {
        if (!isHolesky) return;

        uint256 _deficitBefore = ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 _vaultBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        if (_deficitBefore > _vaultBalanceBefore) {
            assertEq(ynETHWithdrawalQueueManager.deficitRedemptionAssets(), _deficitBefore - _vaultBalanceBefore, "testDeficitRedemptionAssets: E0");
        } else {
            assertEq(ynETHWithdrawalQueueManager.deficitRedemptionAssets(), 0, "testDeficitRedemptionAssets: E1");
        }

        testRequestWithdrawal(_vaultBalanceBefore + 1 ether);
        assertGt(ynETHWithdrawalQueueManager.deficitRedemptionAssets(), _vaultBalanceBefore, "testDeficitRedemptionAssets: E2");
        assertApproxEqAbs(ynETHWithdrawalQueueManager.deficitRedemptionAssets(), _deficitBefore + 1 ether - _vaultBalanceBefore, 1e5, "testDeficitRedemptionAssets: E3");
    }

    function testWithdrawSurplusRedemptionAssets(uint256 _amount) public {
        if (!isHolesky) return;

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), 10 ether);
        uint256 _surplusBefore = ynETHWithdrawalQueueManager.surplusRedemptionAssets();
        uint256 _vaultBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        uint256 _ynETHBalanceBefore = address(yneth).balance;

        if (_amount <= _surplusBefore) {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);
            assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _surplusBefore - _amount, "testWithdrawSurplusRedemptionAssets: E0");
            assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _vaultBalanceBefore - _amount, "testWithdrawSurplusRedemptionAssets: E1");
            assertEq(address(yneth).balance - _ynETHBalanceBefore, _amount, "testWithdrawSurplusRedemptionAssets: E2");
        }
    }

    function testWithdrawSurplusRedemptionAssetsAmountExceedsSurplus(uint256 _amount) public {
        if (!isHolesky) return;

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), 10 ether);
        uint256 _surplusBefore = ynETHWithdrawalQueueManager.surplusRedemptionAssets();
        if (_amount > _surplusBefore) {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            vm.expectRevert(abi.encodeWithSelector(AmountExceedsSurplus.selector, _amount, _surplusBefore));
            ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);
        }
    }

    function testWithdrawSurplusRedemptionAssetsWrongCaller(uint256 _amount) public {
        if (!isHolesky) return;

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), 10 ether);
        uint256 _surplusBefore = ynETHWithdrawalQueueManager.surplusRedemptionAssets();
        if (_amount <= _surplusBefore) {
            vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.REDEMPTION_ASSET_WITHDRAWER_ROLE()));
            ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);
        }
    }

    function testSupportsInterface(bytes4 _interfaceId) public {
        if (!isHolesky) return;

        bool _expected = _interfaceId == type(IERC721).interfaceId;
        assertEq(ynETHWithdrawalQueueManager.supportsInterface(_interfaceId), _expected, "testSupportsInterface: E0");
    }

    // ------------------------------------------
    // Unit tests - ynETHRedemptionAssetsVault
    // ------------------------------------------

    function testInitializationVault() public {
        if (!isHolesky) return;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(new ynETHRedemptionAssetsVault()),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        ynETHRedemptionAssetsVault _ynETHRedemptionAssetsVault = ynETHRedemptionAssetsVault(payable(address(_proxy)));

        address _admin = actors.admin.PROXY_ADMIN_OWNER;
        address _redeemer = address(ynETHWithdrawalQueueManager);
        address _ynETH = address(yneth);
        ynETHRedemptionAssetsVault.Init memory _init = ynETHRedemptionAssetsVault.Init({
            admin: _admin,
            redeemer: _redeemer,
            ynETH: IynETH(address(_ynETH))
        });
        _ynETHRedemptionAssetsVault.initialize(_init);

        assertEq(address(ynETHRedemptionAssetsVaultInstance.ynETH()), _ynETH, "testInitializationVault: E0");
        assertEq(ynETHRedemptionAssetsVaultInstance.hasRole(ynETHRedemptionAssetsVaultInstance.DEFAULT_ADMIN_ROLE(), _admin), true, "testInitializationVault: E1");
        assertEq(ynETHRedemptionAssetsVaultInstance.hasRole(ynETHRedemptionAssetsVaultInstance.REDEEMER_ROLE(), _redeemer), true, "testInitializationVault: E2");
        assertEq(ynETHRedemptionAssetsVaultInstance.hasRole(ynETHRedemptionAssetsVaultInstance.PAUSER_ROLE(), _admin), true, "testInitializationVault: E3");
        assertEq(ynETHRedemptionAssetsVaultInstance.hasRole(ynETHRedemptionAssetsVaultInstance.UNPAUSER_ROLE(), _admin), true, "testInitializationVault: E4");
        assertEq(ynETHRedemptionAssetsVaultInstance.paused(), false, "testInitializationVault: E5");
    }

    function testInitializationVaultInvalid() public {
        if (!isHolesky) return;

        address _admin = actors.admin.PROXY_ADMIN_OWNER;
        address _redeemer = address(ynETHWithdrawalQueueManager);
        address _ynETH = address(yneth);
        ynETHRedemptionAssetsVault.Init memory _init = ynETHRedemptionAssetsVault.Init({
            admin: _admin,
            redeemer: _redeemer,
            ynETH: IynETH(address(_ynETH))
        });

        vm.expectRevert(bytes4(keccak256("InvalidInitialization()")));
        ynETHRedemptionAssetsVaultInstance.initialize(_init);
    }

    function testRedemptionRate() public {
        if (!isHolesky) return;

        uint256 _expected = yneth.previewRedeem(1 ether);
        assertEq(ynETHRedemptionAssetsVaultInstance.redemptionRate(), _expected, "testRedemptionRate: E0");
    }

    function testAvailableRedemptionAssets(uint256 _dealAmount) public {
        if (!isHolesky) return;

        uint256 _expected = address(ynETHRedemptionAssetsVaultInstance).balance;
        assertEq(ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(), _expected, "testAvailableRedemptionAssets: E0");

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), _dealAmount);
        assertEq(ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(), _expected + _dealAmount, "testAvailableRedemptionAssets: E1");
    }

    function testTransferRedemptionAssets(address _to, uint256 _amount, uint256 _dealAmount) public {
        if (!isHolesky) return;

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), _dealAmount);
        uint256 _balanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        uint256 _toBalanceBefore = address(_to).balance;

        if (_balanceBefore >= _amount) {
            vm.prank(address(ynETHWithdrawalQueueManager));
            ynETHRedemptionAssetsVaultInstance.transferRedemptionAssets(_to, _amount);
            assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _balanceBefore - _amount, "testTransferRedemptionAssets: E0");
            assertEq(address(_to).balance - _toBalanceBefore, _amount, "testTransferRedemptionAssets: E1");
        }
    }

    function testTransferRedemptionAssetsInsufficientAssetBalance(address _to, uint256 _amount, uint256 _dealAmount) public {
        if (!isHolesky) return;

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), _dealAmount);
        uint256 _balanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        if (_balanceBefore < _amount) {
            vm.expectRevert(abi.encodeWithSelector(InsufficientAssetBalance.selector, ETH_ASSET, _amount, _balanceBefore));
            vm.prank(address(ynETHWithdrawalQueueManager));
            ynETHRedemptionAssetsVaultInstance.transferRedemptionAssets(_to, _amount);
        }
    }

    function testTransferRedemptionAssetsWrongCaller(address _to, uint256 _amount) public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHRedemptionAssetsVaultInstance.REDEEMER_ROLE()));
        ynETHRedemptionAssetsVaultInstance.transferRedemptionAssets(_to, _amount);
    }

    function testWithdrawRedemptionAssets(uint256 _amount) public {
        if (!isHolesky) return;

        vm.assume(_amount < 100_000 ether);

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), _amount);
        uint256 _balanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        uint256 _ynETHBalanceBefore = address(yneth).balance;

        vm.prank(address(ynETHWithdrawalQueueManager));
        ynETHRedemptionAssetsVaultInstance.withdrawRedemptionAssets(_amount);

        assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _balanceBefore - _amount, "testWithdrawRedemptionAssets: E0");
        assertEq(address(yneth).balance - _ynETHBalanceBefore, _amount, "testWithdrawRedemptionAssets: E1");
    }

    function testWithdrawRedemptionAssetsWrongCaller() public {
        if (!isHolesky) return;

        uint256 _amount = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHRedemptionAssetsVaultInstance.REDEEMER_ROLE()));
        ynETHRedemptionAssetsVaultInstance.withdrawRedemptionAssets(_amount);
    }

    function testPause() public {
        if (!isHolesky) return;

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ynETHRedemptionAssetsVaultInstance.pause();
        assertEq(ynETHRedemptionAssetsVaultInstance.paused(), true, "testPause: E0");

        vm.expectRevert(bytes4(keccak256("ContractPaused()")));
        vm.prank(address(ynETHWithdrawalQueueManager));
        ynETHRedemptionAssetsVaultInstance.transferRedemptionAssets(address(this), 1 ether);

        vm.expectRevert(bytes4(keccak256("ContractPaused()")));
        vm.prank(address(ynETHWithdrawalQueueManager));
        ynETHRedemptionAssetsVaultInstance.withdrawRedemptionAssets(1 ether);
    }

    function testPauseWrongCaller() public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHRedemptionAssetsVaultInstance.PAUSER_ROLE()));
        ynETHRedemptionAssetsVaultInstance.pause();
    }

    function testUnpause() public {
        if (!isHolesky) return;

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ynETHRedemptionAssetsVaultInstance.unpause();
        assertEq(ynETHRedemptionAssetsVaultInstance.paused(), false, "testUnpause: E0");
    }

    function testUnpauseWrongCaller() public {
        if (!isHolesky) return;

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHRedemptionAssetsVaultInstance.UNPAUSER_ROLE()));
        ynETHRedemptionAssetsVaultInstance.unpause();
    }
}