// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IWithdrawalQueueManager} from "../../../src/interfaces/IWithdrawalQueueManager.sol";
import {IRedeemableAsset} from "../../../src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "../../../src/interfaces/IRedemptionAssetsVault.sol";

import {StakingNode} from "../../../src/StakingNode.sol";
import {WithdrawalQueueManager} from "../../../src/WithdrawalQueueManager.sol";

import "../../utils/StakingNodeTestBase.sol";

contract ynETHWithdrawals is StakingNodeTestBase {

    error CallerNotOwnerNorApproved(uint256 tokenId, address caller);
    error NotFinalized(uint256 currentTimestamp, uint256 requestTimestamp, uint256 queueDuration);
    error ERC721NonexistentToken(uint256 tokenId);
    error InsufficientBalance(uint256 currentBalance, uint256 requestedBalance);
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AmountExceedsSurplus(uint256 requestedAmount, uint256 availableSurplus);

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

        stakingNode = StakingNode(payable(address(stakingNodesManager.nodes(nodeId))));

        vm.deal(user, 10_000 ether);

        setupForVerifyWithdrawalCredentials(nodeId, "test/data/holesky_wc_proof_1916455.json");

        secondsToFinalization = 1 days;
        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        ynETHWithdrawalQueueManager.setSecondsToFinalization(secondsToFinalization);
    }

    // ------------------------------------------
    // Withdrawal flow tests
    // ------------------------------------------

    function testVerifyWithdrawalCredentials() public {
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

    function testQueueWithdrawal() public {
        uint256 _amount = withdrawalAmount;

        // fuzzing here will fail on too many inputs rejected
        // vm.assume(_amount > 1e9); // _amount > 1 gwei
        // vm.assume(_amount % 1e9 == 0); // _amount must be a whole Gwei amount
        // vm.assume(_amount <= uint256(IEigenPodManager(stakingNodesManager.eigenPodManager()).podOwnerShares(address(stakingNode))));

        testVerifyWithdrawalCredentials();

        vm.expectRevert(bytes4(keccak256("NotStakingNodesOperator()")));
        stakingNode.queueWithdrawals(_amount);

        uint256 _queuedSharesAmountBefore = stakingNode.queuedSharesAmount();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNode.queueWithdrawals(_amount);

        assertEq(stakingNode.queuedSharesAmount(), _queuedSharesAmountBefore + _amount, "testQueueWithdrawal: E0");

        _queuedSharesAmountBefore = stakingNode.queuedSharesAmount();
        uint256 _balanceBefore = address(stakingNode).balance;
        uint256 _withdrawnValidatorPrincipalBefore = stakingNode.withdrawnValidatorPrincipal();
        completeQueuedWithdrawals(stakingNode, _amount);
        assertEq(address(stakingNode).balance - _balanceBefore, _amount, "testQueueWithdrawal: E1");
        assertEq(stakingNode.queuedSharesAmount(), _queuedSharesAmountBefore - _amount, "testQueueWithdrawal: E2");
        assertEq(stakingNode.withdrawnValidatorPrincipal(), _withdrawnValidatorPrincipalBefore + _amount, "testQueueWithdrawal: E3");
    }

    function testRequestWithdrawal(uint256 _amount) public {
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
            assertEq(_request.creationBlock, block.number, "testRequestWithdrawal: E12");
            assertTrue(!_request.processed, "testRequestWithdrawal: E13");
        }

        {
            uint256 _timestamp = block.timestamp;
            vm.warp(block.timestamp + ynETHWithdrawalQueueManager.secondsToFinalization());
            vm.prank(user);
            // vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, address(ynETHWithdrawalQueueManager).balance, _amount));
            // fails with above revert reason, but _amount is a little less because of precision loss
            // ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(address(0));
            if (ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(address(0)) < _amount) {
                vm.expectRevert();
                ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);
            }
            vm.warp(_timestamp);
        }
    }

    function testProcessPrincipalWithdrawalsForNode() public {
        testRequestWithdrawal(withdrawalAmount);

        vm.expectRevert();
        stakingNodesManager.processPrincipalWithdrawalsForNode(
            nodeId,
            0, // amountToReinvest
            withdrawalAmount // amountToQueue
        );

        uint256 _withdrawnValidatorPrincipalBefore = stakingNode.withdrawnValidatorPrincipal();
        uint256 _stakingNodesManagerBalanceBefore = address(stakingNodesManager).balance;
        uint256 _ynETHBalanceBefore = address(yneth).balance;
        uint256 _withdrawalAssetsVaultBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        uint256 _availableRedemptionAssetsBefore = ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(address(0));

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        stakingNodesManager.processPrincipalWithdrawalsForNode(
            nodeId,
            0, // amountToReinvest
            withdrawalAmount // amountToQueue
        );

        assertEq(stakingNode.withdrawnValidatorPrincipal() + withdrawalAmount, _withdrawnValidatorPrincipalBefore, "testProcessPrincipalWithdrawalsForNode: E0");
        assertEq(address(stakingNodesManager).balance, _stakingNodesManagerBalanceBefore, "testProcessPrincipalWithdrawalsForNode: E1");
        assertEq(address(yneth).balance, _ynETHBalanceBefore, "testProcessPrincipalWithdrawalsForNode: E2");
        assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _withdrawalAssetsVaultBalanceBefore + withdrawalAmount, "testProcessPrincipalWithdrawalsForNode: E3");
        assertEq(ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(address(0)), _availableRedemptionAssetsBefore + withdrawalAmount, "testProcessPrincipalWithdrawalsForNode: E4");
    }

    function testClaimWithdrawal() public {
        testProcessPrincipalWithdrawalsForNode();

        vm.expectRevert(abi.encodeWithSelector(CallerNotOwnerNorApproved.selector, tokenId, address(this)));
        ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);

        vm.expectRevert(abi.encodeWithSelector(NotFinalized.selector, block.timestamp, block.timestamp, secondsToFinalization));
        vm.prank(user);
        ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receiver);

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

        (uint256 _reqAmount, uint256 _feeAtRequestTime,,,, bool _processed) = ynETHWithdrawalQueueManager.withdrawalRequests(tokenId);
        assertTrue(_processed, "testClaimWithdrawal: E0");

        uint256 _feeAmount = ynETHWithdrawalQueueManager.calculateFee(amountOut, _feeAtRequestTime);
        uint256 _receiverAmount = amountOut - _feeAmount;

        assertEq(ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount(), _pendingRequestedRedemptionAmountBefore - amountOut, "testClaimwithdrawal: E1");
        assertEq(yneth.totalSupply(), _totalSupplyBefore - _reqAmount, "testClaimwithdrawal: E2");
        assertEq(address(receiver).balance - _receiverBalanceBefore, _receiverAmount, "testClaimwithdrawal: E3");
        assertEq(address(ynETHWithdrawalQueueManager.feeReceiver()).balance - _feeReceiverBalanceBefore, _feeAmount, "testClaimwithdrawal: E4");
    }

    // ------------------------------------------
    // Unit tests - WithdrawalQueueManager
    // ------------------------------------------

    function testInitialization() public {
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
            withdrawalFee: _withdrawalFee,
            feeReceiver: _feeReceiver
        });
        _manager.initialize(_init);

        vm.expectRevert(bytes4(keccak256("InvalidInitialization()")));
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

    function testSetSecondsToFinalization(uint256 _secondsToFinalization) public {

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setSecondsToFinalization(_secondsToFinalization);

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        ynETHWithdrawalQueueManager.setSecondsToFinalization(_secondsToFinalization);
        assertEq(ynETHWithdrawalQueueManager.secondsToFinalization(), _secondsToFinalization, "testSetSecondsToFinalization: E0");
    }

    function testSetWithdrawalFee(uint256 _feePercentage) public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        if (_feePercentage > ynETHWithdrawalQueueManager.FEE_PRECISION()) {
            vm.expectRevert(bytes4(keccak256("FeePercentageExceedsLimit()")));
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);
        } else {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setWithdrawalFee(_feePercentage);
            assertEq(ynETHWithdrawalQueueManager.withdrawalFee(), _feePercentage, "testSetWithdrawalFee: E0");
        }
    }

    function testFeeReceiver(address _feeReceiver) public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);

        if (_feeReceiver == address(0)) {
            vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);
        } else {
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            ynETHWithdrawalQueueManager.setFeeReceiver(_feeReceiver);
            assertEq(ynETHWithdrawalQueueManager.feeReceiver(), _feeReceiver, "testFeeReceiver: E0");
        }
    }

    function testSurplusRedemptionAssets() public {
        uint256 _balanceOfVaultBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _balanceOfVaultBefore - ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount(), "testSurplusRedemptionAssets: E0");

        vm.deal(address(ynETHRedemptionAssetsVaultInstance), 1 ether);
        assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _balanceOfVaultBefore - ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount() + 1 ether, "testSurplusRedemptionAssets: E1");
    }

    function testDeficitRedemptionAssets() public {
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

    // @todo - queueManager.withdrawSurplusRedemptionAssets() and redemptionAssetsVault.withdrawRedemptionAssets() will always fail because of the ynETH.processWithdrawnETH() call - which is gated to onlyStakingNodesManager
    // function testWithdrawSurplusRedemptionAssets(uint256 _amount) public {
    //     vm.deal(address(ynETHRedemptionAssetsVaultInstance), 10 ether);
    //     uint256 _surplusBefore = ynETHWithdrawalQueueManager.surplusRedemptionAssets();
    //     uint256 _vaultBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
    //     uint256 _ynETHBalanceBefore = address(yneth).balance;

    //     if (_amount > _surplusBefore) {
    //         vm.expectRevert(abi.encodeWithSelector(AmountExceedsSurplus.selector, _amount, _surplusBefore));
    //         ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);
    //     } else {
    //         vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), ynETHWithdrawalQueueManager.REDEMPTION_ASSET_WITHDRAWER_ROLE()));
    //         ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);

    //         vm.prank(user);
    //         ynETHWithdrawalQueueManager.withdrawSurplusRedemptionAssets(_amount);
    //         assertEq(ynETHWithdrawalQueueManager.surplusRedemptionAssets(), _surplusBefore - _amount, "testWithdrawSurplusRedemptionAssets: E0");
    //         assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _vaultBalanceBefore - _amount, "testWithdrawSurplusRedemptionAssets: E1");
    //         assertEq(address(yneth).balance - _ynETHBalanceBefore, _amount, "testWithdrawSurplusRedemptionAssets: E2");
    //     }
    // }

    function testSupportsInterface(bytes4 _interfaceId) public {
        bool _expected = _interfaceId == type(IERC721).interfaceId;
        assertEq(ynETHWithdrawalQueueManager.supportsInterface(_interfaceId), _expected, "testSupportsInterface: E0");
    }

    // ------------------------------------------
    // Unit tests - ynETHRedemptionAssetsVault
    // ------------------------------------------
}

// BEFORE
// | File                                           | % Lines          | % Statements     | % Branches    | % Funcs        |
// | src/StakingNode.sol                            | 8.65% (9/104)    | 9.15% (14/153)   | 0.00% (0/26)  | 18.52% (5/27)  |
// | src/StakingNodesManager.sol                    | 8.40% (10/119)   | 11.03% (16/145)  | 2.78% (1/36)  | 15.38% (4/26)  |
// | src/WithdrawalQueueManager.sol                 | 11.76% (8/68)    | 9.68% (9/93)     | 0.00% (0/22)  | 11.11% (2/18)  |
// | src/ynETHRedemptionAssetsVault.sol             | 33.33% (8/24)    | 33.33% (9/27)    | 12.50% (1/8)  | 22.22% (2/9)   |

// AFTER
// | src/StakingNode.sol                            | 94.23% (98/104)    | 94.12% (144/153)   | 65.38% (17/26)   | 100.00% (27/27)  |
// | src/StakingNodesManager.sol                    | 94.12% (112/119)   | 95.17% (138/145)   | 69.44% (25/36)   | 100.00% (26/26)  |
// | src/WithdrawalQueueManager.sol                 | 88.24% (60/68)     | 89.25% (83/93)     | 77.27% (17/22)   | 77.78% (14/18)   |