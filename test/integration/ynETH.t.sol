// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IEigenPod} from "@eigenlayer-contracts/interfaces/IEigenPod.sol";

import {IStakingNode} from "../../src/interfaces/IStakingNode.sol";

import {ynETH} from "../../src/ynETH.sol";
import {ynBase} from "../../src/ynBase.sol";
import {WithdrawalQueueManager} from "../../src/WithdrawalQueueManager.sol";

import {IntegrationBaseTest, IStakingNodesManager, IRewardsDistributor} from "./IntegrationBaseTest.sol";

import "forge-std/console.sol";

contract ynETHIntegrationTest is IntegrationBaseTest {

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error InvalidInitialization();

    address public user = address(420);
    address public receiver = address(69);

    function testInitializeSetup() public {
        assertEq(yneth.name(), "ynETH", "testInitialize: E0");
        assertEq(yneth.symbol(), "ynETH", "testInitialize: E1");
        assertEq(yneth.hasRole(yneth.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN), true, "testInitialize: E2");
        assertEq(yneth.hasRole(yneth.PAUSER_ROLE(), actors.ops.PAUSE_ADMIN), true, "testInitialize: E3");
        assertEq(yneth.hasRole(yneth.UNPAUSER_ROLE(), actors.admin.UNPAUSE_ADMIN), true, "testInitialize: E4");
        assertEq(address(yneth.stakingNodesManager()), address(stakingNodesManager), "testInitialize: E5");
        assertEq(address(yneth.rewardsDistributor()), address(rewardsDistributor), "testInitialize: E6");
    }

    function testInitializeInvalidInitialization() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(InvalidInitialization.selector);
        yneth.initialize(_init);
    }

    function testInitializeAdminZeroAddress() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: address(0),
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(ynETH.ZeroAddress.selector);
        yneth.initialize(_init);
    }

    function testInitializePauserZeroAddress() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: address(0),
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(ynETH.ZeroAddress.selector);
        yneth.initialize(_init);
    }

    function testInitializeUnpauserZeroAddress() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: address(0),
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(ynETH.ZeroAddress.selector);
        yneth.initialize(_init);
    }

    function testInitializeStakingNodesManagerZeroAddress() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(0)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(ynETH.ZeroAddress.selector);
        yneth.initialize(_init);
    }

    function testInitializeRewardsDistributorZeroAddress() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        ynETH.Init memory _init = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(0)),
            pauseWhitelist: pauseWhitelist
        });

        vm.expectRevert(ynETH.ZeroAddress.selector);
        yneth.initialize(_init);
    }

    function testDepositETH(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);

        vm.deal(user, _amount);

        uint256 _userBalanceBefore = address(user).balance;
        uint256 _recieverBalanceBefore = yneth.balanceOf(receiver);
        uint256 _expectedAmountOut = yneth.previewDeposit(_amount);
        uint256 _expectedAmountOut2 = yneth.convertToShares(_amount);
        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalSupplyBefore = yneth.totalSupply();
        uint256 _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.prank(user);
        uint256 _amountOut = yneth.depositETH{value: _amount}(receiver);

        assertEq(address(user).balance, _userBalanceBefore - _amount, "testDepositETH: E0");
        assertEq(yneth.balanceOf(receiver), _recieverBalanceBefore + _amount, "testDepositETH: E1");
        assertEq(_amountOut, _expectedAmountOut, "testDepositETH: E2");
        assertEq(yneth.totalAssets(), _totalAssetsBefore + _amount, "testDepositETH: E3");
        assertEq(yneth.totalSupply(), _totalSupplyBefore + _amountOut, "testDepositETH: E4");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore + _amount, "testDepositETH: E5");
        assertEq(_expectedAmountOut, _expectedAmountOut2, "testDepositETH: E6");
    }

    function testDepositETHWhenPaused(uint256 _amount) public {

        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();

        vm.deal(user, _amount);

        vm.expectRevert(ynETH.Paused.selector);
        vm.prank(user);
        yneth.depositETH{value: _amount}(user);
    }

    function testDepositETHZeroETH() public {
        vm.expectRevert(ynETH.ZeroETH.selector);
        yneth.depositETH{value: 0}(user);
    }

    function testBurn(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);

        vm.deal(address(ynETHWithdrawalQueueManager), _amount);
        vm.prank(address(ynETHWithdrawalQueueManager));
        yneth.depositETH{value: _amount}(address(ynETHWithdrawalQueueManager));

        uint256 _userBalanceBefore = yneth.balanceOf(address(ynETHWithdrawalQueueManager));
        uint256 _totalSupplyBefore = yneth.totalSupply();
        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.prank(address(ynETHWithdrawalQueueManager));
        yneth.burn(_amount);

        assertEq(yneth.balanceOf(address(ynETHWithdrawalQueueManager)), _userBalanceBefore - _amount, "testBurn: E0");
        assertEq(yneth.totalSupply(), _totalSupplyBefore - _amount, "testBurn: E1");
        assertEq(yneth.totalAssets(), _totalAssetsBefore, "testBurn: E2");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore, "testBurn: E3");
    }

    function testBurnWrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), yneth.BURNER_ROLE()));
        yneth.burn(1 ether);
    }

    function testReceiveRewards(uint256 _depositAmount, uint256 _rewardAmount) public {
        vm.assume(_depositAmount > 0 ether && _depositAmount <= 10_000 ether);
        vm.assume(_rewardAmount > 0 ether && _rewardAmount <= 10_000 ether);

        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalSupplyBefore = yneth.totalSupply();
        uint256 _totalDepositedInPool = yneth.totalDepositedInPool();

        vm.deal(user, _depositAmount);
        vm.prank(user);
        yneth.depositETH{value: _depositAmount}(user);
        
        assertEq(yneth.totalAssets(), _totalAssetsBefore + _depositAmount, "testReceiveRewards: E0");
        assertEq(yneth.totalSupply(), _totalSupplyBefore + _depositAmount, "testReceiveRewards: E1");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPool + _depositAmount, "testReceiveRewards: E2");

        _totalAssetsBefore = yneth.totalAssets();
        _totalSupplyBefore = yneth.totalSupply();
        _totalDepositedInPool = yneth.totalDepositedInPool();

        vm.deal(address(rewardsDistributor), _rewardAmount);
        vm.prank(address(rewardsDistributor));
        yneth.receiveRewards{value: _rewardAmount}();

        assertEq(yneth.totalAssets(), _totalAssetsBefore + _rewardAmount, "testReceiveRewards: E3");
        assertEq(yneth.totalSupply(), _totalSupplyBefore, "testReceiveRewards: E4");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPool + _rewardAmount, "testReceiveRewards: E5");
    }

    function testReceiveRewardsNotRewardsDistributor() public {
        bytes memory encodedError = abi.encodeWithSelector(ynETH.NotRewardsDistributor.selector, address(this));
        vm.expectRevert(encodedError);
        yneth.receiveRewards();
    }

    function testWithdrawETH(uint256 _amount) public {
        vm.assume(_amount > 0 ether && _amount <= 10_000 ether);

        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.deal(user, _amount);
        vm.prank(user);
        yneth.depositETH{value: _amount}(user);

        assertEq(yneth.totalAssets(), _totalAssetsBefore + _amount, "testWithdrawETH: E0");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore + _amount, "testWithdrawETH: E1");

        _totalAssetsBefore = yneth.totalAssets();
        _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.prank(address(stakingNodesManager));
        yneth.withdrawETH(_amount);

        assertEq(yneth.totalAssets(), _totalAssetsBefore - _amount, "testWithdrawETH: E2");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore - _amount, "testWithdrawETH: E3");
    }

    function testWithdrawETHWrongCaller() public {
        address arbitraryCaller = address(0x456);
        vm.deal(arbitraryCaller, 100 ether);
        vm.prank(arbitraryCaller);
        vm.expectRevert(abi.encodeWithSelector(ynETH.CallerNotStakingNodeManager.selector, address(stakingNodesManager), arbitraryCaller));
        yneth.withdrawETH(1 ether);
    }

    function testWithdrawETHInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(ynETH.InsufficientBalance.selector));
        vm.prank(address(stakingNodesManager));
        yneth.withdrawETH(1);
    }

    function testProcessWithdrawnETH(uint256 _amount) public {
        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.deal(address(stakingNodesManager), _amount);
        vm.prank(address(stakingNodesManager));
        yneth.processWithdrawnETH{value: _amount}();

        assertEq(yneth.totalAssets(), _totalAssetsBefore + _amount, "testProcessWithdrawnETH: E0");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore + _amount, "testProcessWithdrawnETH: E1");
    }

    function testProcessWithdrawnETHVault(uint256 _amount) public {
        uint256 _totalAssetsBefore = yneth.totalAssets();
        uint256 _totalDepositedInPoolBefore = yneth.totalDepositedInPool();

        vm.deal(address(stakingNodesManager.redemptionAssetsVault()), _amount);
        vm.prank(address(stakingNodesManager.redemptionAssetsVault()));
        yneth.processWithdrawnETH{value: _amount}();

        assertEq(yneth.totalAssets(), _totalAssetsBefore + _amount, "testProcessWithdrawnETH: E0");
        assertEq(yneth.totalDepositedInPool(), _totalDepositedInPoolBefore + _amount, "testProcessWithdrawnETH: E1");
    }

    function testProcessWithdrawnETHWrongCaller() public {
        address arbitraryCaller = address(0x456);
        vm.deal(arbitraryCaller, 100 ether);
        vm.prank(arbitraryCaller);
        vm.expectRevert(abi.encodeWithSelector(ynETH.CallerNotAuthorized.selector, arbitraryCaller));
        yneth.processWithdrawnETH{value: 1 ether}();
    }

    function testPauseDeposits() public {
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();
        assertTrue(yneth.depositsPaused(), "testPauseDepositETH: E0");

        vm.deal(user, 1 ether);
        vm.expectRevert(ynETH.Paused.selector);
        vm.prank(user);
        yneth.depositETH{value: 1 ether}(user);
    }

    function testPauseDepositsWrongCaller() public {
        address arbitraryCaller = address(0x456);
        vm.prank(arbitraryCaller);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), yneth.PAUSER_ROLE()));
        yneth.pauseDeposits();
    }

    function testUnpauseDeposits() public {

        testPauseDeposits();

        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseDeposits();

        assertFalse(yneth.depositsPaused(), "testUnpauseDeposits: E0");
    }

    function testUnpauseDepositsWrongCaller() public {
        address arbitraryCaller = address(0x456);
        vm.prank(arbitraryCaller);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), yneth.UNPAUSER_ROLE()));
        yneth.unpauseDeposits();
    }

    function testPreviewDeposit() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        // Act
        uint256 shares = yneth.previewDeposit(depositAmount);

        // Assert
        assertTrue(shares > 0, "Preview deposit should return more than 0 shares");
        vm.stopPrank();
    }

    function testTotalAssets() public {
        // Arrange
        uint256 initialTotalAssets = yneth.totalAssets();
        uint256 depositAmount = 1 ether;
        yneth.depositETH{value: depositAmount}(address(this));

        // Act
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();

        // Assert
        assertEq(totalAssetsAfterDeposit, initialTotalAssets + depositAmount, "Total assets should increase by the deposit amount");
    }

    function testFuzzConvertToSharesBeforeAnyDeposits(uint ethAmount) public {

       vm.assume(ethAmount > 0 ether && ethAmount <= 10000 ether);
        // Act
        uint256 sharesBeforeDeposit = yneth.previewDeposit(ethAmount);

        // Assert
        assertEq(sharesBeforeDeposit, ethAmount, "Shares should equal ETH amount before any deposits");
    }

    function testFuzzConvertToSharesAfterFirstDeposit(uint256 firstDepositAmount, uint256 secondDepositAmount) public {
        // Arrange
        vm.assume(firstDepositAmount > 0 ether && firstDepositAmount <= 10000 ether);
        vm.assume(secondDepositAmount > 0 ether && secondDepositAmount <= 10000 ether);
        yneth.depositETH{value: firstDepositAmount}(address(this));

        // Act
        uint256 sharesAfterFirstDeposit = yneth.previewDeposit(secondDepositAmount);

        uint256 expectedShares = secondDepositAmount;

        // Assert
        assertEq(sharesAfterFirstDeposit, expectedShares, "Fuzz: Shares should match expected shares");
        
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();
        // Assert
        assertEq(totalAssetsAfterDeposit, firstDepositAmount, "Total assets should increase by the deposit amount");
    }

    function testFuzzConvertToSharesAfterSecondDeposit(uint256 firstDepositAmount, uint256 secondDepositAmount, uint256 thirdDepositAmount) public {

        vm.assume(firstDepositAmount > 0 ether && firstDepositAmount <= 10000 ether);
        vm.assume(secondDepositAmount > 0 ether && secondDepositAmount <= 10000 ether);
        vm.assume(thirdDepositAmount > 0 ether && thirdDepositAmount <= 10000 ether);

        yneth.depositETH{value: firstDepositAmount}(address(this));

        uint256 totalAssetsAfterFirstDeposit = yneth.totalAssets();
        assertEq(totalAssetsAfterFirstDeposit, firstDepositAmount, "Total assets should match first deposit amount");
        yneth.depositETH{value: secondDepositAmount}(address(this));

        // Assuming initial total assets were equal to firstDepositAmount before rewards
        uint256 expectedTotalAssets = firstDepositAmount + secondDepositAmount; 
        uint256 totalAssetsAfterSecondDeposit = yneth.totalAssets();
        assertEq(totalAssetsAfterSecondDeposit, expectedTotalAssets, "Total assets should match expected total after second deposit");

                // Assuming initial total supply equals shares after first deposit
        uint256 expectedTotalSupply = firstDepositAmount + secondDepositAmount; 
        uint256 totalSupplyAfterSecondDeposit = yneth.totalSupply();
        // TODO: figure out this precision issue
        assertTrue(compareWithThreshold(totalSupplyAfterSecondDeposit, expectedTotalSupply, 1), "Total supply should match expected total supply after second deposit");

        expectedTotalSupply = totalSupplyAfterSecondDeposit;
        // Act
        uint256 sharesAfterSecondDeposit = yneth.previewDeposit(thirdDepositAmount);

        // Using the formula from ynETH to calculate expectedShares
        uint256 expectedShares = Math.mulDiv(
                thirdDepositAmount,
                expectedTotalSupply,
                expectedTotalAssets,
                Math.Rounding.Floor
            );

        // Assert
        assertEq(sharesAfterSecondDeposit, expectedShares, "Shares should equal ETH amount after second deposit");
    }

    function testFuzzConvertToSharesAfterDepositAndRewardsUsingRewardsReceiver(uint256 ethAmount, uint256 rawRewardAmount) public {

        vm.assume(ethAmount > 0 ether && ethAmount <= 10000 ether);
        vm.assume(rawRewardAmount > 0 ether && rawRewardAmount <= 10000 ether);
        // Arrange
        //uint256 ethAmount = 1 ether;
        yneth.depositETH{value: ethAmount}(address(this));
        //uint256 rawRewardAmount = 1 ether;
        // Deal directly to the executionLayerReceiver
        vm.deal(address(executionLayerReceiver), rawRewardAmount);
        // Simulate RewardsDistributor processing rewards which are then forwarded to yneth
        rewardsDistributor.processRewards();
        uint256 expectedNetRewardAmount = rawRewardAmount * 9 / 10;

        // Act
        uint256 sharesAfterDepositAndRewards = yneth.previewDeposit(ethAmount);

        uint256 expectedTotalAssets = ethAmount + expectedNetRewardAmount; // Assuming initial total assets were equal to ethAmount before rewards
        uint256 expectedTotalSupply = ethAmount; // Assuming initial total supply equals shares after first deposit
        // Using the formula from ynETH to calculate expectedShares
        uint256 expectedShares = Math.mulDiv(
                ethAmount,
                expectedTotalSupply,
                expectedTotalAssets,
                Math.Rounding.Floor
            );

        // Assert
        assertTrue(compareWithThreshold(sharesAfterDepositAndRewards, expectedShares, 1), "Shares should be within threshold of 1 of the expected ETH amount after deposit and rewards processed through RewardsReceiver");
    }

    function testRewardsDistributionToYnETHAndFeeReceiver() public {
        // Arrange
        uint256 initialYnETHBalance = address(yneth).balance;
        uint256 initialFeeReceiverBalance = address(actors.admin.FEE_RECEIVER).balance;
        uint256 rewardAmount = 10 ether;
        uint256 expectedFees = rewardAmount * rewardsDistributor.feesBasisPoints() / 10000;
        uint256 expectedNetRewards = rewardAmount - expectedFees;

        // Simulate sending rewards to the executionLayerReceiver
        vm.deal(address(executionLayerReceiver), rewardAmount);

        // Act
        rewardsDistributor.processRewards();

        // Assert
        uint256 finalYnETHBalance = address(yneth).balance;
        uint256 finalFeeReceiverBalance = address(actors.admin.FEE_RECEIVER).balance;

        assertEq(finalYnETHBalance, initialYnETHBalance + expectedNetRewards, "Incorrect ynETH balance after rewards distribution");
        assertEq(finalFeeReceiverBalance, initialFeeReceiverBalance + expectedFees, "Incorrect feeReceiver balance after rewards distribution");
    }

    function testTransferFailsForNonWhitelistedAddresses() public {
        // Arrange
        uint256 transferAmount = 1 ether;
        address nonWhitelistedAddress = address(4); // An arbitrary address not in the whitelist
        address recipient = address(5); // An arbitrary recipient address

        // Act & Assert
        // Ensure transfer from a non-whitelisted address reverts
        vm.expectRevert(ynBase.TransfersPaused.selector);
        vm.prank(nonWhitelistedAddress);
        yneth.transfer(recipient, transferAmount);
    }

    function testTransferSucceedsForWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address whitelistedAddress = actors.eoa.DEFAULT_SIGNER; // Using the pre-defined whitelisted address from setup
        address recipient = address(6); // An arbitrary recipient address


        yneth.depositETH{value: depositAmount}(whitelistedAddress); 

        uint256 transferAmount = yneth.balanceOf(whitelistedAddress);

        // Act
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(whitelist); // Whitelisting the address
        vm.prank(whitelistedAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for whitelisted address");
    }

    function testAddToPauseWhitelist() public {
        // Arrange
        address[] memory addressesToWhitelist = new address[](2);
        addressesToWhitelist[0] = address(1);
        addressesToWhitelist[1] = address(2);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(addressesToWhitelist);

        // Assert
        assertTrue(yneth.pauseWhiteList(addressesToWhitelist[0]), "Address 1 should be whitelisted");
        assertTrue(yneth.pauseWhiteList(addressesToWhitelist[1]), "Address 2 should be whitelisted");
    }

    function testTransferSucceedsForNewlyWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address newWhitelistedAddress = vm.addr(7); // Using a new address for whitelisting
        address recipient = address(8); // An arbitrary recipient address

        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = newWhitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(whitelistAddresses); // Whitelisting the new address
        vm.deal(newWhitelistedAddress, depositAmount); // Providing the new whitelisted address with some ETH
        vm.prank(newWhitelistedAddress);
        yneth.depositETH{value: depositAmount}(newWhitelistedAddress); // Depositing ETH to get ynETH

        uint256 transferAmount = yneth.balanceOf(newWhitelistedAddress);

        // Act
        vm.prank(newWhitelistedAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for newly whitelisted address");
    }

    function testTransferEnabledForAnyAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address arbitraryAddress = vm.addr(9999); // Using an arbitrary address
        address recipient = address(10000); // An arbitrary recipient address

        vm.deal(arbitraryAddress, depositAmount); // Providing the arbitrary address with some ETH
        vm.prank(arbitraryAddress);
        yneth.depositETH{value: depositAmount}(arbitraryAddress); // Depositing ETH to get ynETH

        uint256 transferAmount = yneth.balanceOf(arbitraryAddress);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseTransfers(); // Unpausing transfers for all
        
        vm.prank(arbitraryAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for any address after enabling transfers");
    }

    function testDepositEthWithZeroEth() public {
        bytes memory encodedError = abi.encodeWithSelector(ynETH.ZeroETH.selector);
        vm.expectRevert(encodedError);
        yneth.depositETH{value: 0}(address(this));
    }

    function testPreviewRedeemAfterDepositAndRewards(uint256 _amount, uint256 _rewardAmount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);
        vm.assume(_rewardAmount > 0 && _rewardAmount <= 10_000 ether);

        testDepositETH(_amount);

        uint256 _userBalance = yneth.balanceOf(receiver);
        assertTrue(_userBalance > 0, "testPreviewRedeemAfterDepositAndRewards: E0"); // sanity check
        uint256 _previewRedeemBefore = yneth.previewRedeem(yneth.balanceOf(receiver));
        assertEq(_previewRedeemBefore, _amount, "testPreviewRedeemAfterDepositAndRewards: E1");

        vm.deal(address(executionLayerReceiver), _rewardAmount);
        rewardsDistributor.processRewards();

        assertApproxEqAbs(yneth.previewRedeem(_userBalance), _previewRedeemBefore + (_rewardAmount * 9_000 / 10_000), 10, "testPreviewRedeemAfterDepositAndRewards: E2");
    }

    function testConvertToAssetsAfterDepositAndRewards(uint256 _amount, uint256 _rewardAmount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);
        vm.assume(_rewardAmount > 0 && _rewardAmount <= 10_000 ether);

        testDepositETH(_amount);

        uint256 _userBalance = yneth.balanceOf(receiver);
        assertTrue(_userBalance > 0, "testConvertToAssetsAfterDepositAndRewards: E0");
        uint256 _previewRedeemBefore = yneth.convertToAssets(yneth.balanceOf(receiver));
        assertEq(_previewRedeemBefore, _amount, "testConvertToAssetsAfterDepositAndRewards: E1");

        vm.deal(address(executionLayerReceiver), _rewardAmount);
        rewardsDistributor.processRewards();

        assertApproxEqAbs(yneth.convertToAssets(_userBalance), _previewRedeemBefore + (_rewardAmount * 9_000 / 10_000), 10, "testConvertToAssetsAfterDepositAndRewards: E2");
    }

    function testPreviewRedeemBeforeDeposit(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);
        assertEq(yneth.previewRedeem(_amount), _amount, "testPreviewRedeemBeforeDeposit: E0");
    }

    function testConvertToAssetsBeforeDeposit(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= 10_000 ether);
        assertEq(yneth.convertToAssets(_amount), _amount, "testConvertToAssetsBeforeDeposit: E0");
    }
}


contract ynETHTotalAssetsTest is IntegrationBaseTest {
    function testFuzzTotalAssetsWithDifferentDeposits(uint256 depositAmount1, uint256 depositAmount2) public {
        // Arrange
        vm.assume(depositAmount1 > 0 ether && depositAmount1 <= 10000 ether);
        vm.assume(depositAmount2 > 0 ether && depositAmount2 <= 10000 ether);
        uint256 initialTotalAssets = yneth.totalAssets();

        // Act
        yneth.depositETH{value: depositAmount1}(address(this));
        uint256 totalAssetsAfterFirstDeposit = yneth.totalAssets();
        yneth.depositETH{value: depositAmount2}(address(this));
        uint256 totalAssetsAfterSecondDeposit = yneth.totalAssets();

        // Assert
        assertEq(totalAssetsAfterFirstDeposit, initialTotalAssets + depositAmount1, "Total assets should increase by the first deposit amount");
        assertEq(totalAssetsAfterSecondDeposit, initialTotalAssets + depositAmount1 + depositAmount2, "Total assets should increase by the sum of both deposit amounts");
    }

    function skiptestFuzzTotalAssetsWithRewardsInEigenPods(uint256 depositAmount, uint256 rewardAmount, uint256 stakingNodeCount) public {
        // Arrange
        vm.assume(depositAmount > 0 ether && depositAmount <= 10000 ether);
        vm.assume(rewardAmount > 0 ether && rewardAmount <= 5000 ether); // Assuming rewards are less than or equal to half the deposit for this test
        uint256 maxStakingNodeCount = stakingNodesManager.maxNodeCount();
        vm.assume(stakingNodeCount > 0 && stakingNodeCount <= maxStakingNodeCount);

        yneth.depositETH{value: depositAmount}(address(this));
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();

        assertEq(totalAssetsAfterDeposit, depositAmount, "Total assets should increase by the deposit amount after rewards in eigenPods");

        // deal beacon-chain rewards into eigenpods
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < stakingNodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            IStakingNode stakingNode = stakingNodesManager.createStakingNode();
            IEigenPod eigenPod = stakingNode.eigenPod();
            vm.deal(address(eigenPod), rewardAmount);
            totalRewards += rewardAmount;
            rewardAmount += 1 ether;
        }

        // NOTE: rewards sitting in EigenPods are NOT counted as total TVL
        uint256 totalAssetsAfterRewards = yneth.totalAssets();
        assertEq(totalAssetsAfterRewards, depositAmount, "Total assets should increase by the reward amount in eigenPods");
    }
}