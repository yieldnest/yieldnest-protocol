// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRedemptionAssetsVault} from "../../src/interfaces/IRedemptionAssetsVault.sol";
import {IynETH} from "../../src/interfaces/IynETH.sol";

import {WithdrawalQueueManager, IWithdrawalQueueManager} from "../../src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "../../src/ynETHRedemptionAssetsVault.sol";

import {MockRedeemableYnETH} from "./mocks/MockRedeemableYnETH.sol";

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import "forge-std/Test.sol";

contract ynETHWithdrawalQueueManagerTest is Test {

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    address public admin = address(0x65432);
    address public withdrawalQueueAdmin = address(0x76543);
    address public user = address(0x123456);
    address public feeReceiver = address(0xabc);
    address public redemptionAssetWithdrawer = address(0xdef);
    address public requestFinalizer = address(0xabdef1234567);

    WithdrawalQueueManager public manager;
    MockRedeemableYnETH public redeemableAsset;
    ynETHRedemptionAssetsVault public redemptionAssetsVault;

    // ============================================================================================
    // Setup
    // ============================================================================================

    function setUp() public {

        redeemableAsset = new MockRedeemableYnETH();

        ynETHRedemptionAssetsVault redemptionAssetsVaultImplementation = new ynETHRedemptionAssetsVault();
        TransparentUpgradeableProxy redemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
            address(redemptionAssetsVaultImplementation),
            admin, // admin of the proxy
            ""
        );
        redemptionAssetsVault = ynETHRedemptionAssetsVault(payable(address(redemptionAssetsVaultProxy)));

        WithdrawalQueueManager.Init memory init = WithdrawalQueueManager.Init({
            name: "ynETH Withdrawal",
            symbol: "ynETHW",
            redeemableAsset: redeemableAsset,
            redemptionAssetsVault: IRedemptionAssetsVault((address(redemptionAssetsVault))),
            redemptionAssetWithdrawer: redemptionAssetWithdrawer,
            admin: admin,
            withdrawalQueueAdmin: withdrawalQueueAdmin,
            requestFinalizer: requestFinalizer,
            withdrawalFee: 10000, // 1%
            feeReceiver: feeReceiver
        });

        bytes memory initData = abi.encodeWithSelector(WithdrawalQueueManager.initialize.selector, init);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(new WithdrawalQueueManager()),
            admin, // admin of the proxy
            initData
        );

        manager = WithdrawalQueueManager(payable(address(proxy)));

        ynETHRedemptionAssetsVault.Init memory vaultInit = ynETHRedemptionAssetsVault.Init({
            admin: admin,
            redeemer: address(manager),
            ynETH: IynETH(address(redeemableAsset))
        });
        redemptionAssetsVault.initialize(vaultInit);

        uint256 initialMintAmount = 1_000_000 ether;
        redeemableAsset.mint(user, initialMintAmount);

        // rate is 1:1
        redeemableAsset.setTotalAssets(initialMintAmount);
    }

    function finalizeRequest(uint256 tokenId) internal returns (uint256) {
        vm.prank(requestFinalizer);
        return manager.finalizeRequestsUpToIndex(tokenId + 1);
    }

    function calculateNetEthAndFee(
        uint256 amount, 
        uint256 redemptionRate, 
        uint256 feePercentage
    ) public view returns (uint256 netEthAmount, uint256 feeAmount) {
        uint256 FEE_PRECISION = manager.FEE_PRECISION();
        uint256 ethAmount = amount * redemptionRate / 1e18;
        feeAmount = (ethAmount * feePercentage) / FEE_PRECISION;
        netEthAmount = ethAmount - feeAmount;
        return (netEthAmount, feeAmount);
    }

    // ============================================================================================
    // withdrawalQueueManager.requestWithdrawal
    // ============================================================================================

    function testRequestWithdrawal(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount < 10_000 ether);

        uint256 _pendingRequestedRedemptionAmountBefore = manager.pendingRequestedRedemptionAmount();

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), _amount);
        manager.requestWithdrawal(_amount);
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = manager.withdrawalRequest(0);
        assertEq(_withdrawalRequest.amount, _amount, "testRequestWithdrawal: E0");
        assertEq(_withdrawalRequest.feeAtRequestTime, manager.withdrawalFee(), "testRequestWithdrawal: E1");
        assertEq(_withdrawalRequest.redemptionRateAtRequestTime, redemptionAssetsVault.redemptionRate(), "testRequestWithdrawal: E2");
        assertEq(_withdrawalRequest.creationTimestamp, block.timestamp, "testRequestWithdrawal: E3");
        assertEq(_withdrawalRequest.processed, false, "testRequestWithdrawal: E4");
        assertEq(manager.balanceOf(user), 1, "testRequestWithdrawal: E5");
        assertEq(manager.pendingRequestedRedemptionAmount(), _pendingRequestedRedemptionAmountBefore + _amount, "testRequestWithdrawal: E6");
    }

    function testRequestWithdrawalWithZeroAmount() public {
        uint256 amount = 0;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        vm.expectRevert(WithdrawalQueueManager.AmountMustBeGreaterThanZero.selector);
        manager.requestWithdrawal(amount);
    }

    function testRequestWithdrawalWithMaxUintAmount() public {
        uint256 maxUintAmount = type(uint256).max;
        vm.prank(user);
        redeemableAsset.approve(address(manager), maxUintAmount);
        uint256 userBalance = redeemableAsset.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, userBalance, maxUintAmount));
        manager.requestWithdrawal(maxUintAmount);
    }

    function testRequestWithdrawalWithInsufficientApproval() public {
        uint256 amount = 10 ether;
        uint256 approvedAmount = 1 ether; // Less than the requested amount
        vm.prank(user);
        redeemableAsset.approve(address(manager), approvedAmount);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(manager), approvedAmount, amount));
        manager.requestWithdrawal(amount);
    }

    function testRequestWithdrawalWithExactZeroApproval() public {
        uint256 amount = 10 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), 0);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(manager), 0, amount));
        manager.requestWithdrawal(amount);
    }

    // ============================================================================================
    // withdrawalQueueManager.claimWithdrawal
    // ============================================================================================

    function testClaimWithdrawalSuccesfully(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount < 10_000 ether);

        vm.deal(address(redemptionAssetsVault), _amount);

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), _amount);
        uint256 tokenId = manager.requestWithdrawal(_amount);
        vm.stopPrank();

        uint256 _redemptionRateAtRequestTime = redemptionAssetsVault.redemptionRate();

        uint256 finalizationId = finalizeRequest(tokenId);

        uint256 _userBalanceBefore = user.balance;
        uint256 _vaultBalanceBefore = address(redemptionAssetsVault).balance;
        vm.prank(user);
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: tokenId, receiver: user , finalizationId: finalizationId }
            )
        );

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "testClaimWithdrawal: E0");
        assertEq(request.amount, _amount, "testClaimWithdrawal: E1");
        assertEq(request.feeAtRequestTime, manager.withdrawalFee(), "testClaimWithdrawal: E2");
        assertEq(request.redemptionRateAtRequestTime, _redemptionRateAtRequestTime, "testClaimWithdrawal: E3");

        uint256 expectedFeeAmount = (_amount * request.feeAtRequestTime) / manager.FEE_PRECISION();
        uint256 expectedNetEthAmount = (_amount * request.redemptionRateAtRequestTime) / 1e18 - expectedFeeAmount;
        assertEq(user.balance, expectedNetEthAmount, "testClaimWithdrawal: E5");
        assertEq(redeemableAsset.balanceOf(address(manager)), 0, "testClaimWithdrawal: E6");
        assertEq(feeReceiver.balance, expectedFeeAmount, "testClaimWithdrawal: E7");
        assertApproxEqAbs(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, 1000, "testClaimWithdrawal: E8");
        assertEq(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, "testClaimWithdrawal: E8");
        assertEq(manager.balanceOf(user), 0, "testClaimWithdrawal: E9");
        assertEq(user.balance - _userBalanceBefore, expectedNetEthAmount, "testClaimWithdrawal: E10");
    }

    function testClaimWithdrawalRevertsWhenInsufficientVaultBalance() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        uint256 tokenId = manager.requestWithdrawal(amount);

        uint256 finalizationId = finalizeRequest(tokenId);

        // Ensure vault has insufficient balance
        uint256 insufficientAmount = amount - 1;
        (bool success, ) = address(redemptionAssetsVault).call{value: insufficientAmount}("");
        require(success, "Ether transfer failed");

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueueManager.InsufficientBalance.selector, 
                insufficientAmount, 
                amount
            )
        );
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: 0, receiver: user , finalizationId: finalizationId }
            )
        );

    }

    function testClaimOneWithdrawalNotFinalized() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        uint256 tokenId = manager.requestWithdrawal(amount);

        // Attempt to claim before time is up
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.InvalidFinalizationId.selector, 0));
        vm.prank(user);
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: tokenId, receiver: user , finalizationId: 0 }
            )
        );
    }

    function testClaimWithdrawalForNonExistentTokenId() public {
        uint256 nonExistentTokenId = 9999; // Assuming this tokenId does not exist
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, nonExistentTokenId, user));

        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: nonExistentTokenId, receiver: user , finalizationId: 0 }
            )
        );
    }

    function testClaimWithdrawalForAlreadyProcessedWithdrawal() public {
        uint256 amount = 10 ether; // Example amount to process withdrawal
        uint256 availableRedemptionAmount = 100 ether;

        // Simulate user requesting a withdrawal
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        uint256 tokenId = manager.requestWithdrawal(amount);

        uint256 finalizationId = finalizeRequest(tokenId);

        // Send exact Ether to vault
        (bool success, ) = address(redemptionAssetsVault).call{value: availableRedemptionAmount}("");
        require(success, "Ether transfer failed");

        // Attempt to claim the withdrawal
        vm.prank(user);
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: tokenId, receiver: user , finalizationId: finalizationId }
            )
        );

        // Attempt to claim the withdrawal again to ensure it cannot be processed twice
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, tokenId, user));
        vm.prank(user);
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: tokenId, receiver: user , finalizationId: finalizationId }
            )
        );
    }
    
    function testtestClaimWithdrawalNotOwner() public {
        uint256 tokenId = 1; // Assuming this tokenId exists and is owned by another user
        address notOwner = vm.addr(9999); // An arbitrary address that is not the owner
        

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, tokenId, notOwner));
        manager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                tokenId: tokenId, receiver: notOwner, finalizationId: 0 }
            )
        );
    }

    // ============================================================================================
    // withdrawalQueueManager.claimWithdrawals
    // ============================================================================================

    function testclaimWithdrawals(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount < 10_000 ether);

        vm.deal(address(redemptionAssetsVault), _amount);

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), _amount);
        uint256 tokenId = manager.requestWithdrawal(_amount);
        vm.stopPrank();

        uint256 _redemptionRateAtRequestTime = redemptionAssetsVault.redemptionRate();

        uint256 finalizationId = finalizeRequest(tokenId);

        uint256 _userBalanceBefore = user.balance;
        uint256 _vaultBalanceBefore = address(redemptionAssetsVault).balance;
        IWithdrawalQueueManager.WithdrawalClaim[] memory claims = new IWithdrawalQueueManager.WithdrawalClaim[](1);
        claims[0] = IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: tokenId,
            finalizationId: finalizationId,
            receiver: user
        });

        vm.prank(user);
        manager.claimWithdrawals(claims);

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "testclaimWithdrawals: E0");
        assertEq(request.amount, _amount, "testclaimWithdrawals: E1");
        assertEq(request.feeAtRequestTime, manager.withdrawalFee(), "testclaimWithdrawals: E2");
        assertEq(request.redemptionRateAtRequestTime, _redemptionRateAtRequestTime, "testclaimWithdrawals: E3");

        uint256 expectedFeeAmount = (_amount * request.feeAtRequestTime) / manager.FEE_PRECISION();
        uint256 expectedNetEthAmount = (_amount * request.redemptionRateAtRequestTime) / 1e18 - expectedFeeAmount;
        assertEq(user.balance, expectedNetEthAmount, "testclaimWithdrawals: E5");
        assertEq(redeemableAsset.balanceOf(address(manager)), 0, "testclaimWithdrawals: E6");
        assertEq(feeReceiver.balance, expectedFeeAmount, "testclaimWithdrawals: E7");
        assertApproxEqAbs(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, 1000, "testclaimWithdrawals: E8");
        assertEq(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, "testclaimWithdrawals: E8");
        assertEq(manager.balanceOf(user), 0, "testclaimWithdrawals: E9");
        assertEq(user.balance - _userBalanceBefore, expectedNetEthAmount, "testclaimWithdrawals: E10");
    }

    function testClaimWithdrawalsWithIncreasedRedemptionRate() public {
        uint256 initialAmount = 100 ether;

        // Deal ETH to redemptionAssetsVault
        uint256 vaultBalance = 1000 ether; // Set an arbitrary balance for the vault
        vm.deal(address(redemptionAssetsVault), vaultBalance);

        // User requests withdrawal
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), initialAmount);
        uint256 tokenId = manager.requestWithdrawal(initialAmount);
        vm.stopPrank();

        uint256 initialRedemptionRate = redemptionAssetsVault.redemptionRate();
        assertEq(initialRedemptionRate, 1e18, "Initial redemption rate should be 1:1");

        uint256 finalizationId = finalizeRequest(tokenId);

        // Increase total assets, which should increase the redemption rate
        uint256 currentTotalAssets = redeemableAsset.totalAssets();
        uint256 increasedAmount = currentTotalAssets + (currentTotalAssets * 20 / 100);
        redeemableAsset.setTotalAssets(increasedAmount);

        uint256 newRedemptionRate = redemptionAssetsVault.redemptionRate();
        assertGt(newRedemptionRate, initialRedemptionRate, "Redemption rate should have increased");

        uint256 userBalanceBefore = user.balance;

        vm.prank(user);
        IWithdrawalQueueManager.WithdrawalClaim[] memory claims = new IWithdrawalQueueManager.WithdrawalClaim[](1);
        claims[0] = IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: tokenId,
            receiver: user,
            finalizationId: finalizationId
        });
        manager.claimWithdrawals(claims);

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "Request should be processed");

        // Calculate expected amounts
        uint256 expectedFeeAmount = (initialAmount * request.feeAtRequestTime) / manager.FEE_PRECISION();
        uint256 expectedNetEthAmount = (initialAmount * request.redemptionRateAtRequestTime) / 1e18 - expectedFeeAmount;

        // Verify that the user received the correct amount based on the initial redemption rate
        assertEq(user.balance - userBalanceBefore, expectedNetEthAmount, "User should receive ETH based on initial redemption rate");

        // Verify that the manager's balance of redeemable asset is zero
        assertEq(redeemableAsset.balanceOf(address(manager)), 0, "Manager should have no redeemable assets left");

        // Verify that the fee receiver received the correct fee
        assertEq(feeReceiver.balance, expectedFeeAmount, "Fee receiver should receive correct fee amount");
    }

    function testClaimWithdrawalsWithDecreasedRedemptionRate() public {

        // Log the fee percentage
        uint256 feePercentage = manager.withdrawalFee();

        uint256 initialAmount = 100 ether;

        // Deal ETH to redemptionAssetsVault
        uint256 vaultBalance = 1000 ether;
        vm.deal(address(redemptionAssetsVault), vaultBalance);

        // User requests withdrawal
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), initialAmount);
        uint256 tokenId = manager.requestWithdrawal(initialAmount);
        vm.stopPrank();

        uint256 initialRedemptionRate = redemptionAssetsVault.redemptionRate();
        assertEq(initialRedemptionRate, 1e18, "Initial redemption rate should be 1:1");


        // Decrease total assets, which should decrease the redemption rate
        uint256 currentTotalAssets = redeemableAsset.totalAssets();
        uint256 decreasedAmount = currentTotalAssets - (currentTotalAssets * 20 / 100);
        redeemableAsset.setTotalAssets(decreasedAmount);

        uint256 newRedemptionRate = redemptionAssetsVault.redemptionRate();
        assertLt(newRedemptionRate, initialRedemptionRate, "Redemption rate should have decreased");

        // finalize request at the new rate
        uint256 finalizationId = finalizeRequest(tokenId);
        {
            // Assert finalization fields
            IWithdrawalQueueManager.Finalization memory finalization = manager.getFinalization(finalizationId);
            assertEq(finalization.startIndex, 0, "Start index should be 0");
            assertEq(finalization.endIndex, tokenId + 1, "End index should be tokenId + 1");
            assertEq(finalization.redemptionRate, newRedemptionRate, "Finalization redemption rate should match new rate");
        }

        uint256 userBalanceBefore = user.balance;

        vm.prank(user);
        manager.claimWithdrawal(IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: tokenId,
            finalizationId: finalizationId,
            receiver: user
        }));

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "Request should be processed");

        // Calculate expected amounts
        (uint256 expectedNetEthAmount, uint256 expectedFeeAmount) = calculateNetEthAndFee(initialAmount,newRedemptionRate, feePercentage);

        // Verify that the user received the correct amount based on the new (lower) redemption rate
        assertEq(user.balance - userBalanceBefore, expectedNetEthAmount, "User should receive ETH based on new (lower) redemption rate");

        // Verify that the manager's balance of redeemable asset is zero
        assertEq(redeemableAsset.balanceOf(address(manager)), 0, "Manager should have no redeemable assets left");

        // Verify that the fee receiver received the correct fee
        assertEq(feeReceiver.balance, expectedFeeAmount, "Fee receiver should receive correct fee amount");
    }


    function testclaimWithdrawalWithComputedFinalizationId(
            uint256 _amount
        ) public {
        vm.assume(_amount > 0 && _amount < 10_000 ether);

        vm.deal(address(redemptionAssetsVault), _amount);

        uint256 extraWithdrawalsBefore = 3;
        {
            address anotherUser = address(0x9876);
            vm.deal(anotherUser, 100 ether);
            redeemableAsset.mint(anotherUser, 100 ether);
            // Increase total assets of redeemableAsset by 100 ether to maintain ratio
            vm.prank(admin);
            redeemableAsset.setTotalAssets(redeemableAsset.totalAssets() + 100 ether);

            // Perform 3 withdrawal requests of 1 ether each for anotherUser
            for (uint256 i = 0; i < extraWithdrawalsBefore; i++) {
                vm.startPrank(anotherUser);
                redeemableAsset.approve(address(manager), 1 ether);
                manager.requestWithdrawal(1 ether);
                vm.stopPrank();

                // finalize immediately
                finalizeRequest(i);
            }
        }

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), _amount);
        uint256 tokenId = manager.requestWithdrawal(_amount);
        vm.stopPrank();

        uint256 _redemptionRateAtRequestTime = redemptionAssetsVault.redemptionRate();

        finalizeRequest(tokenId);


        uint256 extraWithdrawalsAfter = 2;
        {
            address anotherUser = address(0x9876);
            vm.deal(anotherUser, 100 ether);
            redeemableAsset.mint(anotherUser, 100 ether);
            // Increase total assets of redeemableAsset by 100 ether to maintain ratio
            vm.prank(admin);
            redeemableAsset.setTotalAssets(redeemableAsset.totalAssets() + 100 ether);

            // Perform 3 withdrawal requests of 1 ether each for anotherUser
            for (uint256 i = 0; i < extraWithdrawalsAfter; i++) {
                vm.startPrank(anotherUser);
                redeemableAsset.approve(address(manager), 1 ether);
                manager.requestWithdrawal(1 ether);
                vm.stopPrank();

                // finalize immediately
                finalizeRequest(i + tokenId + 1);
            }
        }

        uint256 _userBalanceBefore = user.balance;
        uint256 _vaultBalanceBefore = address(redemptionAssetsVault).balance;

        vm.prank(user);
        manager.claimWithdrawal(tokenId, user);

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "testclaimWithdrawals: E0");
        assertEq(request.amount, _amount, "testclaimWithdrawals: E1");
        assertEq(request.feeAtRequestTime, manager.withdrawalFee(), "testclaimWithdrawals: E2");
        assertEq(request.redemptionRateAtRequestTime, _redemptionRateAtRequestTime, "testclaimWithdrawals: E3");

        uint256 expectedFeeAmount = (_amount * request.feeAtRequestTime) / manager.FEE_PRECISION();
        uint256 expectedNetEthAmount = (_amount * request.redemptionRateAtRequestTime) / 1e18 - expectedFeeAmount;
        assertEq(user.balance, expectedNetEthAmount, "testclaimWithdrawals: E5");
        assertEq(redeemableAsset.balanceOf(address(manager)), (extraWithdrawalsBefore + extraWithdrawalsAfter) * 1 ether, "testclaimWithdrawals: E6");
        assertEq(feeReceiver.balance, expectedFeeAmount, "testclaimWithdrawals: E7");
        assertApproxEqAbs(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, 1000, "testclaimWithdrawals: E8");
        assertEq(address(redemptionAssetsVault).balance, _vaultBalanceBefore - _amount, "testclaimWithdrawals: E8");
        assertEq(manager.balanceOf(user), 0, "testclaimWithdrawals: E9");
        assertEq(user.balance - _userBalanceBefore, expectedNetEthAmount, "testclaimWithdrawals: E10");
    }

    // ============================================================================================
    // withdrawalQueueManager.surplusRedemptionAssets
    // ============================================================================================

    function testSurplusRedemptionAssets() public {
        assertEq(redemptionAssetsVault.availableRedemptionAssets(), 0, "testSurplusRedemptionAssets: E0");
        assertEq(manager.pendingRequestedRedemptionAmount(), 0, "testSurplusRedemptionAssets: E1");
        assertEq(manager.surplusRedemptionAssets(), 0, "testSurplusRedemptionAssets: E2");

        vm.deal(address(redemptionAssetsVault), 100 ether);
        assertEq(redemptionAssetsVault.availableRedemptionAssets(), 100 ether, "testSurplusRedemptionAssets: E3");
        assertEq(manager.pendingRequestedRedemptionAmount(), 0, "testSurplusRedemptionAssets: E4");
        assertEq(manager.surplusRedemptionAssets(), 100 ether, "testSurplusRedemptionAssets: E5");
    }

    // ============================================================================================
    // withdrawalQueueManager.surplusRedemptionAssets
    // ============================================================================================

    function testDeficitRedemptionAssets() public {
        assertEq(redemptionAssetsVault.availableRedemptionAssets(), 0, "testDeficitRedemptionAssets: E0");
        assertEq(manager.pendingRequestedRedemptionAmount(), 0, "testDeficitRedemptionAssets: E1");
        assertEq(manager.deficitRedemptionAssets(), 0, "testDeficitRedemptionAssets: E2");

        vm.deal(address(redemptionAssetsVault), 100 ether);
        assertEq(redemptionAssetsVault.availableRedemptionAssets(), 100 ether, "testDeficitRedemptionAssets: E3");
        assertEq(manager.pendingRequestedRedemptionAmount(), 0, "testDeficitRedemptionAssets: E4");
        assertEq(manager.deficitRedemptionAssets(), 0, "testDeficitRedemptionAssets: E5");

        uint256 amount = 50 ether;
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        manager.requestWithdrawal(amount);
        vm.stopPrank();
        assertEq(manager.pendingRequestedRedemptionAmount(), amount, "testDeficitRedemptionAssets: E6");
        assertEq(manager.deficitRedemptionAssets(), 0, "testDeficitRedemptionAssets: E7");

        amount = 100 ether;
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        manager.requestWithdrawal(amount);
        vm.stopPrank();

        assertEq(manager.pendingRequestedRedemptionAmount(), 150 ether, "testDeficitRedemptionAssets: E8");
        assertEq(manager.deficitRedemptionAssets(), 50 ether, "testDeficitRedemptionAssets: E9");
    }

    // ============================================================================================
    // withdrawalQueueManager.withdrawSurplusRedemptionAssets
    // ============================================================================================

    function testWithdrawSurplusRedemptionAssets() public {
        uint256 amount = 100 ether;
        vm.deal(address(redemptionAssetsVault), amount);
        assertEq(manager.surplusRedemptionAssets(), amount, "testWithdrawSurplusRedemptionAssets: E0");

        uint256 _ynethBalanceBefore = address(redeemableAsset).balance;

        vm.prank(redemptionAssetWithdrawer);
        manager.withdrawSurplusRedemptionAssets(amount);

        assertEq(manager.surplusRedemptionAssets(), 0, "testWithdrawSurplusRedemptionAssets: E1");
        assertEq(address(redeemableAsset).balance - _ynethBalanceBefore, amount, "testWithdrawSurplusRedemptionAssets: E2");
    }

    function testWithdrawSurplusRedemptionAssetsAmountExceedsSurplus() public {
        uint256 amount = 100 ether;
        vm.deal(address(redemptionAssetsVault), amount);
        assertEq(manager.surplusRedemptionAssets(), amount, "testWithdrawSurplusRedemptionAssetsAmountExceedsSurplus: E0");

        uint256 _ynethBalanceBefore = address(redeemableAsset).balance;

        uint256 amountExceedingSurplus = amount + 1;
        vm.prank(redemptionAssetWithdrawer);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.AmountExceedsSurplus.selector, amountExceedingSurplus, amount));
        manager.withdrawSurplusRedemptionAssets(amountExceedingSurplus);

        assertEq(manager.surplusRedemptionAssets(), amount, "testWithdrawSurplusRedemptionAssetsAmountExceedsSurplus: E1");
        assertEq(address(redeemableAsset).balance - _ynethBalanceBefore, 0, "testWithdrawSurplusRedemptionAssetsAmountExceedsSurplus: E2");
    }

    // ============================================================================================
    // withdrawalQueueManager.withdrawalRequestIsFinalized / withdrawalQueueManager.isFinalized
    // ============================================================================================

    function testWithdrawalRequestIsFinalized() public {
        uint256 amount = 100 ether;
        vm.deal(address(redemptionAssetsVault), amount);
        assertEq(manager.surplusRedemptionAssets(), amount, "testWithdrawalRequestIsFinalized: E0");

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        uint256 tokenId = manager.requestWithdrawal(amount);
        vm.stopPrank();

        assertEq(manager.withdrawalRequestIsFinalized(tokenId), false, "testWithdrawalRequestIsFinalized: E1");

        finalizeRequest(tokenId);
        assertEq(manager.withdrawalRequestIsFinalized(tokenId), true, "testWithdrawalRequestIsFinalized: E3");
    }

    // ============================================================================================
    // withdrawalQueueManager.withdrawalRequest
    // ============================================================================================

    function testWithdrawalRequest() public {
        uint256 amount = 100 ether;
        vm.deal(address(redemptionAssetsVault), amount);
        assertEq(manager.surplusRedemptionAssets(), amount, "testWithdrawalRequest: E0");

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        uint256 tokenId = manager.requestWithdrawal(amount);
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertEq(request.amount, amount, "testWithdrawalRequest: E1");
        assertEq(request.feeAtRequestTime, manager.withdrawalFee(), "testWithdrawalRequest: E2");
        assertEq(request.redemptionRateAtRequestTime, redemptionAssetsVault.redemptionRate(), "testWithdrawalRequest: E3");
        assertEq(request.creationTimestamp, block.timestamp, "testWithdrawalRequest: E4");
        assertEq(request.processed, false, "testWithdrawalRequest: E5");
    }

    // ============================================================================================
    // withdrawalQueueManager.supportsInterface
    // ============================================================================================

    function testSupportsInterface() public {
        bytes4 interfaceId = 0x80ac58cd; // IERC721
        assertEq(manager.supportsInterface(interfaceId), true, "testSupportsInterface: E0");
    }

    // ============================================================================================
    // withdrawalQueueManager.setWithdrawalFee
    // ============================================================================================

    function testSetWithdrawalFee(uint256 _feePercentage) public {
        vm.assume(_feePercentage <= manager.FEE_PRECISION());

        assertEq(manager.withdrawalFee(), 10000, "testSetWithdrawalFee: E0"); // from setUp

        vm.prank(withdrawalQueueAdmin);
        manager.setWithdrawalFee(_feePercentage);

        assertEq(manager.withdrawalFee(), _feePercentage, "testSetWithdrawalFee: E1");
    }

    function testSetWithdrawalFeeFeePercentageExceedsLimit() public {
        uint256 _feePercentage = manager.FEE_PRECISION() + 1;
        vm.prank(withdrawalQueueAdmin);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.FeePercentageExceedsLimit.selector));
        manager.setWithdrawalFee(_feePercentage);
    }

    function testSetWithdrawalFeeWrongCaller() public {
        uint256 _feePercentage = 1;
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), manager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        manager.setWithdrawalFee(_feePercentage);
    }

    // ============================================================================================
    // withdrawalQueueManager.setFeeReceiver
    // ============================================================================================

    function testSetFeeReceiver() public {
        address newFeeReceiver = vm.addr(9999);
        assertEq(manager.feeReceiver(), feeReceiver, "testSetFeeReceiver: E0"); // from setUp

        vm.prank(withdrawalQueueAdmin);
        manager.setFeeReceiver(newFeeReceiver);

        assertEq(manager.feeReceiver(), newFeeReceiver, "testSetFeeReceiver: E1");
    }

    function testSetFeeReceiverZeroAddress() public {
        address zeroAddress = address(0);
        vm.prank(withdrawalQueueAdmin);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.ZeroAddress.selector));
        manager.setFeeReceiver(zeroAddress);
    }

    function testSetFeeReceiverWrongCaller() public {
        address newFeeReceiver = vm.addr(9999);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), manager.WITHDRAWAL_QUEUE_ADMIN_ROLE()));
        manager.setFeeReceiver(newFeeReceiver);
    }

    // ============================================================================================
    // ynETHRedemptionAssetsVault.finalizeRequestsUpToIndex
    // ============================================================================================

    function testFinalizeRequestsUpToIndexSuccessfullyForMultipleRequests(uint256 _amount, uint256 requestIncrease) public {

        vm.assume(_amount > 0 && _amount < 10_000 ether);
        vm.assume(requestIncrease >= 0 && requestIncrease < 1000 ether);
        uint256 requestIndex = 5;

        uint256[] memory requestedAmounts = new uint256[](requestIndex);
        for (uint256 i = 0; i < requestIndex; i++) {
            requestedAmounts[i] = _amount + requestIncrease * i;
        }

        // requesting withdrawals to the vault
        for (uint256 i = 0; i < requestIndex; i++) {
            vm.startPrank(user);
            redeemableAsset.approve(address(manager), requestedAmounts[i]);
            manager.requestWithdrawal(requestedAmounts[i]);
            vm.stopPrank();

            vm.deal(address(redemptionAssetsVault), requestedAmounts[i]);
        }
        
        // Finalize requests up to the specified index
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);

        // Check if the requests up to the specified index are finalized
        for (uint256 i = 0; i < requestIndex; i++) {
            bool isFinalized = manager.withdrawalRequestIsFinalized(i);
            assertTrue(isFinalized, string.concat("Request ", vm.toString(i), " should be finalized"));
        }
    }

    function testFinalizeRequestsUpToIndexWrongCaller() public {
        uint256 requestIndex = 3;
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                address(this),
                manager.REQUEST_FINALIZER_ROLE()
                )
        );
        manager.finalizeRequestsUpToIndex(requestIndex);
    }

    function testFinalizeRequestsUpToIndexWithInvalidIndex() public {
        uint256 requestIndex = 999; // Assuming an index that is out of bounds
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueueManager.IndexExceedsTokenCount.selector, 
                requestIndex, 
                manager._tokenIdCounter()
            )
        );
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);
    }

    function testFinalizeRequestsNotAdvanced() public {

        // Make a withdrawal request
        uint256 amount = 1 ether;
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        manager.requestWithdrawal(amount);
        vm.stopPrank();

        // Ensure the request was made successfully
        assertEq(manager._tokenIdCounter(), 1, "Token counter should be incremented");
        
        // Finalize the request
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(1);

        // Check if the request is finalized
        bool isFinalized = manager.withdrawalRequestIsFinalized(0);
        assertTrue(isFinalized, "Request should be finalized");

        // Verify lastFinalizedIndex
        assertEq(manager.lastFinalizedIndex(), 1, "lastFinalizedIndex should be updated");


        uint256 initialFinalizedIndex = manager.lastFinalizedIndex();
        uint256 requestIndex = initialFinalizedIndex; // Same as the last finalized index to trigger IndexNotAdvanced error

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueueManager.IndexNotAdvanced.selector, 
                requestIndex, 
                initialFinalizedIndex
            )
        );
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);
    }

    function testFinalizeRequestsUpToIndexWithPreExistingRequest() public {
        // Setup: Create a pre-existing request
        uint256 amount = 1 ether;
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), amount);
        uint256 tokenId = manager.requestWithdrawal(amount);
        vm.stopPrank();

        // Attempt to finalize up to the request index including the pre-existing request
        uint256 requestIndex = tokenId + 1; // Index 0 is the pre-existing request
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);

        // Check if the pre-existing request is finalized
        bool isFinalized = manager.withdrawalRequestIsFinalized(0);
        assertTrue(isFinalized, "Pre-existing request should be finalized");

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueueManager.IndexNotAdvanced.selector, 
                requestIndex, 
                requestIndex
            )
        );
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);
    }

    function testFinalizeRequestsUpToIndexWithNoExistingRequests() public {
        // Check initial state
        assertEq(manager.lastFinalizedIndex(), 0, "Initial lastFinalizedIndex should be 0");
        assertEq(manager._tokenIdCounter(), 0, "Initial _tokenIdCounter should be 0");
        
        uint256 requestIndex = 0;
        // Attempt to finalize (should revert)
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.IndexNotAdvanced.selector, requestIndex, requestIndex));
        vm.prank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(requestIndex);
    }

    // ============================================================================================
    // ynETHRedemptionAssetsVault.findFinalizationForTokenId
    // ============================================================================================

    function testFindFinalizationForTokenId() public {
        // Create 12 withdrawal requests
        uint256[] memory amounts = new uint256[](12);
        uint256[] memory tokenIds = new uint256[](12);
        for (uint256 i = 0; i < 12; i++) {
            amounts[i] = 1 ether * (i + 1);
            vm.startPrank(user);
            redeemableAsset.approve(address(manager), amounts[i]);
            tokenIds[i] = manager.requestWithdrawal(amounts[i]);
            vm.stopPrank();
        }

        // Finalize requests in 5 batches
        vm.startPrank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(2);  // Finalization 0: tokenIds 0-1
        manager.finalizeRequestsUpToIndex(5);  // Finalization 1: tokenIds 2-4
        manager.finalizeRequestsUpToIndex(8);  // Finalization 2: tokenIds 5-7
        manager.finalizeRequestsUpToIndex(9); // Finalization 3: tokenIds 8-8
        manager.finalizeRequestsUpToIndex(12); // Finalization 4: tokenIds 9-11
        vm.stopPrank();

        // Test finding finalization for each token ID
        uint256[] memory expectedFinalizationIds = new uint256[](12);
        expectedFinalizationIds[0] = 0;
        expectedFinalizationIds[1] = 0;
        expectedFinalizationIds[2] = 1;
        expectedFinalizationIds[3] = 1;
        expectedFinalizationIds[4] = 1;
        expectedFinalizationIds[5] = 2;
        expectedFinalizationIds[6] = 2;
        expectedFinalizationIds[7] = 2;
        expectedFinalizationIds[8] = 3;
        expectedFinalizationIds[9] = 4;
        expectedFinalizationIds[10] = 4;
        expectedFinalizationIds[11] = 4;
        for (uint256 i = 0; i < 12; i++) {
            uint256 actualFinalizationId = manager.findFinalizationForTokenId(tokenIds[i]);
            assertEq(actualFinalizationId, expectedFinalizationIds[i], string(abi.encodePacked("Incorrect finalization ID for token ", vm.toString(tokenIds[i]))));
        }

        // Test finding finalization for non-existent token ID
        uint256 nonExistentTokenId = 100;
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.NotFinalized.selector, nonExistentTokenId));
        manager.findFinalizationForTokenId(nonExistentTokenId);
    }

    function testFindFinalizationForTokenIdWithOneFinalization() public {
        // Create 3 withdrawal requests
        uint256[] memory amounts = new uint256[](3);
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = 1 ether * (i + 1);
            vm.startPrank(user);
            redeemableAsset.approve(address(manager), amounts[i]);
            tokenIds[i] = manager.requestWithdrawal(amounts[i]);
            vm.stopPrank();
        }

        // Finalize all requests in one batch
        vm.startPrank(requestFinalizer);
        manager.finalizeRequestsUpToIndex(3);  // Finalization 0: tokenIds 0-2
        vm.stopPrank();

        // Test finding finalization for each token ID
        for (uint256 i = 0; i < 3; i++) {
            uint256 actualFinalizationId = manager.findFinalizationForTokenId(tokenIds[i]);
            assertEq(actualFinalizationId, 0, string(abi.encodePacked("Incorrect finalization ID for token ", vm.toString(tokenIds[i]))));
        }

        // Test finding finalization for non-existent token ID
        uint256 nonExistentTokenId = 100;
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.NotFinalized.selector, nonExistentTokenId));
        manager.findFinalizationForTokenId(nonExistentTokenId);
    }

    function testFindFinalizationForTokenIdWithNoFinalizations() public {
        // Create a withdrawal request
        vm.startPrank(user);
        redeemableAsset.approve(address(manager), 1 ether);
        uint256 tokenId = manager.requestWithdrawal(1 ether);
        vm.stopPrank();

        // Attempt to find finalization for the token ID without any finalizations
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.NotFinalized.selector, tokenId));
        manager.findFinalizationForTokenId(tokenId);
    }

    // ============================================================================================
    // ynETHRedemptionAssetsVault.pause
    // ============================================================================================

    function testPause() public {
        assertEq(redemptionAssetsVault.paused(), false, "testPause: E0");

        vm.prank(admin);
        redemptionAssetsVault.pause();

        assertEq(redemptionAssetsVault.paused(), true, "testPause: E1");

        vm.expectRevert(abi.encodeWithSelector(ynETHRedemptionAssetsVault.ContractPaused.selector));
        vm.prank(address(manager));
        redemptionAssetsVault.transferRedemptionAssets(user, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(ynETHRedemptionAssetsVault.ContractPaused.selector));
        vm.prank(address(manager));
        redemptionAssetsVault.withdrawRedemptionAssets(1 ether);
    }

    function testPauseWrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), redemptionAssetsVault.PAUSER_ROLE()));
        redemptionAssetsVault.pause();
    }

    function testUnpause() public {
        vm.prank(admin);
        redemptionAssetsVault.pause();
        assertEq(redemptionAssetsVault.paused(), true, "testUnpause: E0");

        vm.prank(admin);
        redemptionAssetsVault.unpause();
        assertEq(redemptionAssetsVault.paused(), false, "testUnpause: E1");
    }

    function testUnpauseWrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), redemptionAssetsVault.UNPAUSER_ROLE()));
        redemptionAssetsVault.unpause();
    }

    // ============================================================================================
    // withdrawalRequestsForOwner
    // ============================================================================================

    function testWithdrawalRequestsForOwner() public {

        address anotherUser = address(0x9876);
        vm.deal(anotherUser, 100 ether);


        // Mint initial ynETH tokens for users
        redeemableAsset.mint(user, 100 ether);
        redeemableAsset.mint(anotherUser, 100 ether);

        // Setup: Create multiple withdrawal requests for different users with varying amounts
        uint256[] memory requestAmounts = new uint256[](4);
        requestAmounts[0] = 1 ether;
        requestAmounts[1] = 2.5 ether;
        requestAmounts[2] = 0.75 ether;
        requestAmounts[3] = 3.2 ether;


        vm.startPrank(user);
        redeemableAsset.approve(address(manager), 10 ether); // Approve enough for all transactions
        uint256 request1 = manager.requestWithdrawal(requestAmounts[0]);
        uint256 request2 = manager.requestWithdrawal(requestAmounts[1]);
        uint256 request3 = manager.requestWithdrawal(requestAmounts[2]);
        vm.stopPrank();
        // Store the request IDs in an array for easy access and verification
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = request1;
        requestIds[1] = request2;
        requestIds[2] = request3;

        vm.startPrank(anotherUser);
        redeemableAsset.approve(address(manager), requestAmounts[3]);
        manager.requestWithdrawal(requestAmounts[3]);
        vm.stopPrank();

        // Test: Retrieve withdrawal requests for the main user
        (uint256[] memory withdrawalIndexes, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) = manager.withdrawalRequestsForOwner(user);

        // Assertions
        assertEq(withdrawalIndexes.length, requestIds.length, "Incorrect number of withdrawal indexes");
        assertEq(requests.length, requestIds.length, "Incorrect number of withdrawal requests");

        // Verify the content of each request
        for (uint256 i = 0; i < requestIds.length; i++) {
            assertEq(withdrawalIndexes[i], i, "Incorrect withdrawal index");
            assertEq(requests[i].amount, requestAmounts[i], "Incorrect withdrawal amount");
            assertTrue(requests[i].creationTimestamp > 0, "Invalid creation timestamp");
            assertFalse(requests[i].processed, "Request should not be claimed");
        }

        // Test: Retrieve withdrawal requests for the other user
        (withdrawalIndexes, requests) = manager.withdrawalRequestsForOwner(anotherUser);

        // Assertions for the other user
        assertEq(withdrawalIndexes.length, 1, "Incorrect number of withdrawal indexes for other user");
        assertEq(requests.length, 1, "Incorrect number of withdrawal requests for other user");
        assertEq(withdrawalIndexes[0], 3, "Incorrect withdrawal index for other user");
        assertEq(requests[0].amount, requestAmounts[3], "Incorrect withdrawal amount for other user");

        assertTrue(requests[0].creationTimestamp > 0, "Invalid creation timestamp for other user");
        assertFalse(requests[0].processed, "Request should not be claimed for other user");

        // Test: Retrieve withdrawal requests for an address with no requests
        address noRequestUser = address(0x1111);
        (withdrawalIndexes, requests) = manager.withdrawalRequestsForOwner(noRequestUser);

        // Assertions for address with no requests
        assertEq(withdrawalIndexes.length, 0, "Should be no withdrawal indexes for address with no requests");
        assertEq(requests.length, 0, "Should be no withdrawal requests for address with no requests");
    }
}