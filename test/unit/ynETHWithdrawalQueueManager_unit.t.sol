// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRedemptionAssetsVault} from "../../src/interfaces/IRedemptionAssetsVault.sol";
import {IynETH} from "../../src/interfaces/IynETH.sol";

import {WithdrawalQueueManager, IWithdrawalQueueManager} from "../../src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "../../src/ynETHRedemptionAssetsVault.sol";

import {MockRedeemableYnETH} from "./mocks/MockRedeemableYnETH.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "forge-std/Test.sol";

contract ynETHWithdrawalQueueManagerTest is Test {

    address public admin = address(0x65432);
    address public withdrawalQueueAdmin = address(0x76543);
    address public user = address(0x123456);
    address public feeReceiver = address(0xabc);
    address public redemptionAssetWithdrawer = address(0xdef);

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

        vm.prank(withdrawalQueueAdmin);
        manager.setSecondsToFinalization(3 * 24 * 3600); // 3 days to finalize

        uint256 initialMintAmount = 1_000_000 ether;
        redeemableAsset.mint(user, initialMintAmount);

        // rate is 1:1
        redeemableAsset.setTotalAssets(initialMintAmount);
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

    function testClaimWithdrawal(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount < 10_000 ether);

        console.log("0redemptionAssetsVault.redemptionRate():", redemptionAssetsVault.redemptionRate());

        vm.deal(address(redemptionAssetsVault), _amount);

        console.log("1redemptionAssetsVault.redemptionRate():", redemptionAssetsVault.redemptionRate());

        vm.startPrank(user);
        redeemableAsset.approve(address(manager), _amount);
        manager.requestWithdrawal(_amount);
        vm.stopPrank();

        console.log("2redemptionAssetsVault.redemptionRate():", redemptionAssetsVault.redemptionRate());

        // uint256 _redemptionRateAtRequestTime = redemptionAssetsVault.redemptionRate();

        vm.warp(block.timestamp + manager.secondsToFinalization() + 1);

        console.log("3redemptionAssetsVault.redemptionRate():", redemptionAssetsVault.redemptionRate());

        uint256 _userBalanceBefore = user.balance;
        uint256 _vaultBalanceBefore = address(redemptionAssetsVault).balance;
        uint256 tokenId = 0;
        vm.prank(user);
        manager.claimWithdrawal(tokenId, user);

        console.log("4redemptionAssetsVault.redemptionRate():", redemptionAssetsVault.redemptionRate());
        console.log("userClaimedAmount:", user.balance - _userBalanceBefore);
        console.log("vaultBalance:", _vaultBalanceBefore - address(redemptionAssetsVault).balance);
        console.log("amount:", _amount);

        IWithdrawalQueueManager.WithdrawalRequest memory request = manager.withdrawalRequest(tokenId);
        assertTrue(request.processed, "testClaimWithdrawal: E0");
        assertEq(request.amount, _amount, "testClaimWithdrawal: E1");
        assertEq(request.feeAtRequestTime, manager.withdrawalFee(), "testClaimWithdrawal: E2");
        assertEq(request.redemptionRateAtRequestTime, redemptionAssetsVault.redemptionRate(), "testClaimWithdrawal: E3");
        assertEq(request.creationTimestamp, block.timestamp - manager.secondsToFinalization() - 1, "testClaimWithdrawal: E4");

        uint256 expectedFeeAmount = (_amount * request.feeAtRequestTime) / manager.FEE_PRECISION();
        uint256 expectedNetEthAmount = (_amount * request.redemptionRateAtRequestTime) / 1e18 - expectedFeeAmount;
        assertEq(user.balance, expectedNetEthAmount, "testClaimWithdrawal: E5");
        assertEq(redeemableAsset.balanceOf(address(manager)), 0, "testClaimWithdrawal: E6");
        assertEq(feeReceiver.balance, expectedFeeAmount, "testClaimWithdrawal: E7");
    }

    function testClaimWithdrawalRevertsWhenInsufficientVaultBalance() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        manager.requestWithdrawal(amount);

        // Fast forward time to pass the finalization period
        vm.warp(block.timestamp + manager.secondsToFinalization() + 1);

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
        manager.claimWithdrawal(0, user);
    }

    function testFailClaimWithdrawalNotFinalized() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        manager.requestWithdrawal(amount);
        uint256 tokenId = 0; // Assuming tokenId starts from 0 after the first request

        // Attempt to claim before time is up
        vm.prank(user);
        vm.expectRevert(WithdrawalQueueManager.NotFinalized.selector);
        manager.claimWithdrawal(tokenId, user);
    }

    function testClaimWithdrawalForNonExistentTokenId() public {
        uint256 nonExistentTokenId = 9999; // Assuming this tokenId does not exist
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, nonExistentTokenId, user));
        manager.claimWithdrawal(nonExistentTokenId, user);
    }

    function testClaimWithdrawalForAlreadyProcessedWithdrawal() public {
        uint256 tokenId = 0; // Assuming this tokenId is unprocessed
        uint256 amount = 10 ether; // Example amount to process withdrawal
        uint256 availableRedemptionAmount = 100 ether;

        // Simulate user requesting a withdrawal
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        manager.requestWithdrawal(amount);

        // Fast forward time to pass the finalization period
        vm.warp(block.timestamp + manager.secondsToFinalization() + 1);

        // Send exact Ether to vault
        (bool success, ) = address(redemptionAssetsVault).call{value: availableRedemptionAmount}("");
        require(success, "Ether transfer failed");

        // Attempt to claim the withdrawal
        vm.prank(user);
        manager.claimWithdrawal(tokenId, user);

        // Attempt to claim the withdrawal again to ensure it cannot be processed twice
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, tokenId, user));
        manager.claimWithdrawal(tokenId, user);
    }
    
    function testWithdrawalOfNotNFTOwner() public {
        uint256 tokenId = 1; // Assuming this tokenId exists and is owned by another user
        address notOwner = vm.addr(9999); // An arbitrary address that is not the owner
        

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueManager.CallerNotOwnerNorApproved.selector, tokenId, notOwner));
        manager.claimWithdrawal(tokenId, notOwner);
    }
}
