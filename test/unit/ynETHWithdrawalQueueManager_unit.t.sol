// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ynETHWithdrawalQueueManager} from "src/ynETHWithdrawalQueueManager.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import "test/unit/mocks/MockRedeemableYnETH.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ynETHWithdrawalQueueManagerTest is Test {
    ynETHWithdrawalQueueManager manager;
    MockRedeemableYnETH redeemableAsset;
    address admin = address(0x65432);
    address withdrawalQueueAdmin = address(0x76543);
    address user = address(0x123456);

    function setUp() public {
        redeemableAsset = new MockRedeemableYnETH();


        ynETHWithdrawalQueueManager.Init memory init = WithdrawalQueueManager.Init({
            name: "ynETH Withdrawal",
            symbol: "ynETHW",
            redeemableAsset: address(redeemableAsset),
            admin: admin,
            withdrawalQueueAdmin: withdrawalQueueAdmin,
            withdrawalFee: 100, // 1%
            feeReceiver: address(0xabc)
        });

        bytes memory initData = abi.encodeWithSelector(WithdrawalQueueManager.initialize.selector, init);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(new ynETHWithdrawalQueueManager()),
            admin, // admin of the proxy
            initData
        );
        manager = ynETHWithdrawalQueueManager(address(proxy));

        vm.prank(withdrawalQueueAdmin);
        manager.setSecondsToFinalization(3 * 24 * 3600); // 3 days to finalize

        uint256 initialMintAmount = 10000 ether;
        redeemableAsset.mint(user, initialMintAmount);
    }

    function testRequestWithdrawal() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        redeemableAsset.approve(address(manager), amount);
        vm.prank(user);
        manager.requestWithdrawal(amount);
        IWithdrawalQueueManager.WithdrawalRequest memory withdrawalRequest = manager.withdrawalRequest(0);
        assertEq(withdrawalRequest.amount, amount, "Stored amount should match requested amount");

        assertEq(withdrawalRequest.feeAtRequestTime, manager.withdrawalFee(), "Stored fee should match current withdrawal fee");
        assertEq(withdrawalRequest.redemptionRateAtRequestTime, manager.getRedemptionRate(), "Stored redemption rate should match current redemption rate");
        assertEq(withdrawalRequest.creationTimestamp, block.timestamp, "Stored creation timestamp should match current block timestamp");
        assertEq(withdrawalRequest.creationBlock, block.number, "Stored creation block should match current block number");
        assertEq(withdrawalRequest.processed, false, "Stored processed status should be false");

        uint256 userBalance = manager.balanceOf(user);
        assertEq(userBalance, 1, "User should have 1 NFT representing the withdrawal request");
    }

    // function testClaimWithdrawal() public {
    //     uint256 amount = 1 ether;
    //     vm.prank(user);
    //     manager.requestWithdrawal(amount);
    //     uint256 tokenId = 1;

    //     // Fast forward time to pass the finalization period
    //     vm.warp(block.timestamp + manager.secondsToFinalization() + 1);

    //     vm.prank(user);
    //     manager.claimWithdrawal(tokenId);
    //     bool processed = manager.withdrawalRequests(tokenId).processed;
    //     assertTrue(processed, "Withdrawal should be marked as processed");
    // }

    // function testFailClaimWithdrawalNotFinalized() public {
    //     uint256 amount = 1 ether;
    //     vm.prank(user);
    //     manager.requestWithdrawal(amount);
    //     uint256 tokenId = 1;

    //     // Attempt to claim before time is up
    //     vm.prank(user);
    //     manager.claimWithdrawal(tokenId);
    // }

    // function testSetSecondsToFinalization() public {
    //     uint256 newTime = 1000;
    //     vm.prank(withdrawalQueueAdmin);
    //     manager.setSecondsToFinalization(newTime);
    //     assertEq(manager.secondsToFinalization(), newTime, "Seconds to finalization should be updated");
    // }

    // function testSetWithdrawalFee() public {
    //     uint256 newFee = 200; // 2%
    //     vm.prank(withdrawalQueueAdmin);
    //     manager.setWithdrawalFee(newFee);
    //     assertEq(manager.withdrawalFee(), newFee, "Withdrawal fee should be updated");
    // }
}
