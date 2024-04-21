// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./IntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "src/external/chainlink/AggregatorV3Interface.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces//IPausable.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {TestLSDStakingNodeV2} from "test/mocks/TestLSDStakingNodeV2.sol";
import {TestYnLSDV2} from "test/mocks/TestYnLSDV2.sol";
import {ynBase} from "src/ynBase.sol";

contract ynLSDAssetTest is IntegrationBaseTest {
    function testDepositSTETHFailingWhenStrategyIsPaused() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();
        
		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this), amount);
        assertEq(compareRebasingTokenBalances(asset.balanceOf(address(this)), balance), true, "Amount not received");
        vm.stopPrank();

        asset.approve(address(ynlsd), amount);

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = amount;

        vm.prank(chainAddresses.eigenlayer.STRATEGY_MANAGER_PAUSER_ADDRESS);
        IPausable(address(strategyManager)).pause(1);

        vm.expectRevert(bytes("Pausable: index is paused"));
        vm.prank(actors.ops.LSD_RESTAKING_MANAGER);
        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }

    function testDepositSTETHSuccessWithOneDeposit() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 32 ether;

        uint256 initialSupply = ynlsd.totalSupply();

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this), amount);
        assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");

        stETH.approve(address(ynlsd), balance);
        ynlsd.deposit(stETH, balance, address(this));

        assertEq(ynlsd.balanceOf(address(this)), ynlsd.totalSupply() - initialSupply, "ynlsd balance does not match total supply");
    }
    
    function testDepositSTETHSuccessWithMultipleDeposits() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 32 ether;

        uint256 initialSupply = ynlsd.totalSupply();

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this),amount);
        assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");

        stETH.approve(address(ynlsd), 32 ether);
        uint256 depositAmountOne = 5 ether;
        uint256 depositAmountTwo = 3 ether;
        uint256 depositAmountThree = 7 ether;

        ynlsd.deposit(stETH, depositAmountOne, address(this));
        ynlsd.deposit(stETH, depositAmountTwo, address(this));
        ynlsd.deposit(stETH, depositAmountThree, address(this));

        assertEq(ynlsd.balanceOf(address(this)), ynlsd.totalSupply() - initialSupply, "ynlsd balance does not match total supply");
    }
    
    function testDespositUnsupportedAsset() public {
        IERC20 asset = IERC20(address(1));
        uint256 amount = 1 ether;
        address receiver = address(this);

        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(asset)));
        ynlsd.deposit(asset, amount, receiver);
    }
    
    function testDepositWithZeroAmount() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 0; // Zero amount for deposit
        address receiver = address(this);

        vm.expectRevert(ynLSD.ZeroAmount.selector);
        ynlsd.deposit(asset, amount, receiver);
    }

    function testConvertToShares() public {
        IERC20 asset = IERC20(address(this));
        uint256 amount = 1000;
        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(asset)));
        ynlsd.convertToShares(asset, amount);
    }

    function testConvertToSharesBootstrapStrategy() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
        uint256[] memory totalAssets = ynlsd.getTotalAssets();
        ynlsd.nodes(0);
        
        uint256 bootstrapAmountUnits = ynlsd.BOOTSTRAP_AMOUNT_UNITS() * 1e18 - 1;
        assertTrue(compareWithThreshold(totalAssets[0], bootstrapAmountUnits, 1), "Total assets should be equal to bootstrap amount");
    }

    function testConvertToSharesZeroStrategy() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
        uint256[] memory totalAssets = ynlsd.getTotalAssets();
        ynlsd.nodes(0);

        assertEq(totalAssets[1], 0, "Total assets should be equal to bootstrap 0");
    }

    function testGetTotalAssets() public {
        uint256 totalAssetsInETH = ynlsd.convertToETH(ynlsd.assets(0), ynlsd.BOOTSTRAP_AMOUNT_UNITS() * 1e18 - 1);
        uint256 totalAssets = ynlsd.totalAssets();
        assertTrue(compareWithThreshold(totalAssets, totalAssetsInETH, 1), "Total assets should be equal to bootstrap amount converted to its ETH value");
    }
    
    function testLSDWrongStrategy() public {
        // IERC20 asset = IERC20(address(1));
        // vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(asset)));
        // TODO: Come back to this
    }

    function testGetSharesForAsset() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.lsd.RETH_FEED_ADDRESS);

        // Call the getSharesForAsset function
        uint256 shares = ynlsd.convertToShares(asset, amount);
        (, int256 price, , uint256 timeStamp, ) = assetPriceFeed.latestRoundData();

        // assertEq(ynlsd.totalAssets(), 0);
        // assertEq(ynlsd.totalSupply(), 0);

        assertEq(timeStamp > 0, true, "Zero timestamp");
        assertEq(price > 0, true, "Zero price");
        assertEq(block.timestamp - timeStamp < 86400, true, "Price stale for more than 24 hours");
        assertEq(shares, (uint256(price) * amount) / 1e18, "Total shares don't match");
    }

    function testTotalAssetsAfterDeposit() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        IPausable pausableStrategyManager = IPausable(address(strategyManager));
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

        uint256 totalAssetsBeforeDeposit = ynlsd.totalAssets();
        
		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this), amount);
        assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");
        asset.approve(address(ynlsd), balance);
        ynlsd.deposit(asset, balance, address(this));


        {
            IERC20[] memory assets = new IERC20[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = asset;
            amounts[0] = amount;

            vm.prank(actors.ops.LSD_RESTAKING_MANAGER);

            lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
        }

        uint256 totalAssetsAfterDeposit = ynlsd.totalAssets();

        uint256 oraclePrice = yieldNestOracle.getLatestPrice(address(asset));

        IStrategy strategy = ynlsd.strategies(IERC20(chainAddresses.lsd.STETH_ADDRESS));
        uint256 balanceInStrategyForNode  = strategy.userUnderlyingView((address(lsdStakingNode)));
        
        uint256 expectedBalance = balanceInStrategyForNode * oraclePrice / 1e18;

        // Assert that totalAssets reflects the deposit
        assertEq(
            compareWithThreshold(totalAssetsAfterDeposit - totalAssetsBeforeDeposit,expectedBalance, 1), true, 
            "Total assets do not reflect the deposit"
        );
    }

    function testPreviewDeposit() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(chainAddresses.lsd.STETH_FEED_ADDRESS);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 stethPrice = uint256(price);

        uint256 expectedDepositPreview = amount * stethPrice / 1e18;
        uint256 previewDeposit = ynlsd.previewDeposit(asset, amount);
        assertEq(previewDeposit, expectedDepositPreview, "Preview deposit does not match expected value");
    }

    function testConvertToETH() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(chainAddresses.lsd.STETH_FEED_ADDRESS);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 stethPrice = uint256(price);

        uint256 expectedDepositPreview = amount * stethPrice / 1e18;

        uint256 ethAmount = ynlsd.convertToETH(asset, amount);
        assertEq(ethAmount, expectedDepositPreview, "convertToEth does not match expected value");
    }
}

contract ynLSDAdminTest is IntegrationBaseTest {

    function testCreateLSDStakingNode() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        uint256 expectedNodeId = 0;
        assertEq(lsdStakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreateStakingNodeLSDOverMax() public {
        vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
        for (uint256 i = 0; i < 10; i++) {
            ynlsd.createLSDStakingNode();
        }
        vm.expectRevert(abi.encodeWithSelector(ynLSD.TooManyStakingNodes.selector, 10));
        ynlsd.createLSDStakingNode();
        vm.stopPrank();
    } 

    function testCreate2LSDStakingNodes() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance1 = ynlsd.createLSDStakingNode();
        uint256 expectedNodeId1 = 0;
        assertEq(lsdStakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance2 = ynlsd.createLSDStakingNode();
        uint256 expectedNodeId2 = 1;
        assertEq(lsdStakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

    function testCreateLSDStakingNodeAfterUpgradeWithoutUpgradeability() public {
        // Upgrade the ynLSD implementation to TestYnLSDV2
        address newImplementation = address(new TestYnLSDV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newImplementation, "");

        // Attempt to create a LSD staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
    }

    function testUpgradeLSDStakingNodeImplementation() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        // upgrade the ynLSD to support the new initialization version.
        address newYnLSDImpl = address(new TestYnLSDV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newYnLSDImpl, "");

        TestLSDStakingNodeV2 testLSDStakingNodeV2 = new TestLSDStakingNodeV2();
        vm.prank(actors.admin.STAKING_ADMIN);
        ynlsd.upgradeLSDStakingNodeImplementation(address(testLSDStakingNodeV2));

        UpgradeableBeacon beacon = ynlsd.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, address(testLSDStakingNodeV2));

        TestLSDStakingNodeV2 testLSDStakingNodeV2Instance = TestLSDStakingNodeV2(payable(address(lsdStakingNodeInstance)));
        uint256 redundantFunctionResult = testLSDStakingNodeV2Instance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(testLSDStakingNodeV2Instance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testFailRegisterLSDStakingNodeImplementationTwice() public {
        address initialImplementation = address(new TestLSDStakingNodeV2());
        ynlsd.registerLSDStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new TestLSDStakingNodeV2());
        vm.expectRevert("ynLSD: Implementation already exists");
        ynlsd.registerLSDStakingNodeImplementationContract(newImplementation);
    }

    function testRegisterLSDStakingNodeImplementationAlreadyExists() public {
        // address initialImplementation = address(new TestLSDStakingNodeV2());
        // vm.startPrank(actors.STAKING_ADMIN);
        // ynlsd.registerLSDStakingNodeImplementationContract(initialImplementation);

        // // vm.expectRevert("ynLSD: Implementation already exists");

        // ynlsd.registerLSDStakingNodeImplementationContract(initialImplementation);
        // vm.stopPrank();
        // TODO: Come back to this
    }

    function testRetrieveAssetsNotLSDStakingNode() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
        vm.expectRevert(abi.encodeWithSelector(ynLSD.NotLSDStakingNode.selector, address(this), 0));
        ynlsd.retrieveAsset(0, asset, amount);
    }

    function testRetrieveAssetsUnsupportedAsset() public {
        // come back to this
    }

    function testRetrieveTransferExceedsBalance() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();

        ILSDStakingNode lsdStakingNode = ynlsd.nodes(0);

        vm.startPrank(address(lsdStakingNode));
        vm.expectRevert();
        ynlsd.retrieveAsset(0, asset, amount);
        vm.stopPrank();
    }

    function testRetrieveAssetsSuccess() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 64 ether;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();

        ILSDStakingNode lsdStakingNode = ynlsd.nodes(0);
        vm.deal(address(lsdStakingNode), 1000);

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this), amount);
       assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");

        asset.approve(address(ynlsd), balance);
        ynlsd.deposit(asset, balance, address(this));

        vm.startPrank(address(lsdStakingNode));
        asset.approve(address(ynlsd), 32 ether);
        ynlsd.retrieveAsset(0, asset, balance);
        vm.stopPrank();
    }

    function testSetMaxNodeCount() public {
        uint256 maxNodeCount = 10;
        vm.prank(actors.admin.STAKING_ADMIN);
        ynlsd.setMaxNodeCount(maxNodeCount);
        assertEq(ynlsd.maxNodeCount(), maxNodeCount, "Max node count does not match expected value");
    }

    function testPauseDepositsFunctionality() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        uint256 depositAmount = 0.1 ether;

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_stETH(address(this), depositAmount);
        stETH.approve(address(ynlsd), balance);

        // Arrange
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.updateDepositsPaused(true);

        // Act & Assert
        bool pauseState = ynlsd.depositsPaused();
        assertTrue(pauseState, "Deposit ETH should be paused after setting pause state to true");

        // Trying to deposit ETH while pause
        vm.expectRevert(ynLSD.Paused.selector);
        ynlsd.deposit(stETH, balance, address(this));

        // Unpause and try depositing again
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.updateDepositsPaused(false);
        pauseState = ynlsd.depositsPaused();

        assertFalse(pauseState, "Deposit ETH should be unpaused after setting pause state to false");

        // Deposit should succeed now
        ynlsd.deposit(stETH, balance, address(this));
        assertGt(ynlsd.totalAssets(), 0, "ynLSD balance should be greater than 0 after deposit");
    }

}

contract ynLSDTransferPauseTest is IntegrationBaseTest {

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

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), depositAmount);
        stETH.approve(address(ynlsd), balance);
        ynlsd.deposit(stETH, balance, whitelistedAddress); 

        uint256 transferAmount = ynlsd.balanceOf(whitelistedAddress);

        // Act
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedAddress;
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.addToPauseWhitelist(whitelist); // Whitelisting the address
        vm.prank(whitelistedAddress);
        ynlsd.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynlsd.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for whitelisted address");
    }

    function testAddToPauseWhitelist() public {
        // Arrange
        address[] memory addressesToWhitelist = new address[](2);
        addressesToWhitelist[0] = address(1);
        addressesToWhitelist[1] = address(2);

        // Act
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.addToPauseWhitelist(addressesToWhitelist);

        // Assert
        assertTrue(ynlsd.pauseWhiteList(addressesToWhitelist[0]), "Address 1 should be whitelisted");
        assertTrue(ynlsd.pauseWhiteList(addressesToWhitelist[1]), "Address 2 should be whitelisted");
    }

    function testTransferSucceedsForNewlyWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address newWhitelistedAddress = vm.addr(7); // Using a new address for whitelisting
        address recipient = address(8); // An arbitrary recipient address

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), depositAmount);

        stETH.approve(address(ynlsd), balance);
        ynlsd.deposit(stETH, balance, newWhitelistedAddress);

        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = newWhitelistedAddress;
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.addToPauseWhitelist(whitelistAddresses); // Whitelisting the new address

        uint256 transferAmount = ynlsd.balanceOf(newWhitelistedAddress);

        // Act
        vm.prank(newWhitelistedAddress);
        ynlsd.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynlsd.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for newly whitelisted address");
    }

    function testTransferEnabledForAnyAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address arbitraryAddress = vm.addr(9999); // Using an arbitrary address
        address recipient = address(10000); // An arbitrary recipient address

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 balance = testAssetUtils.get_stETH(address(this), depositAmount);
        stETH.approve(address(ynlsd), balance);
        ynlsd.deposit(stETH, balance, arbitraryAddress);

        uint256 transferAmount = ynlsd.balanceOf(arbitraryAddress);

        // Act
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.unpauseTransfers(); // Unpausing transfers for all
        
        vm.prank(arbitraryAddress);
        ynlsd.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynlsd.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for any address after enabling transfers");
    }

    function testRemoveInitialWhitelistedAddress() public {
        // Arrange
        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = actors.eoa.DEFAULT_SIGNER; // EOA address to be removed from whitelist

        // Act
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.removeFromPauseWhitelist(whitelistAddresses); // Removing the EOA address from whitelist

        // Assert
        bool isWhitelisted = ynlsd.pauseWhiteList(actors.eoa.DEFAULT_SIGNER);
        assertFalse(isWhitelisted, "EOA address was not removed from whitelist");
    }

    function testRemoveMultipleNewWhitelistAddresses() public {
        // Arrange
        address[] memory newWhitelistAddresses = new address[](2);
        newWhitelistAddresses[0] = address(20000); // First new whitelist address
        newWhitelistAddresses[1] = address(20001); // Second new whitelist address

        // Adding addresses to whitelist first
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.addToPauseWhitelist(newWhitelistAddresses);

        // Act
        vm.prank(actors.admin.PAUSE_ADMIN);
        ynlsd.removeFromPauseWhitelist(newWhitelistAddresses); // Removing the new whitelist addresses

        // Assert
        bool isFirstAddressWhitelisted = ynlsd.pauseWhiteList(newWhitelistAddresses[0]);
        bool isSecondAddressWhitelisted = ynlsd.pauseWhiteList(newWhitelistAddresses[1]);
        assertFalse(isFirstAddressWhitelisted, "First new whitelist address was not removed");
        assertFalse(isSecondAddressWhitelisted, "Second new whitelist address was not removed");
    }
}


contract ynLSDDonationsTest is IntegrationBaseTest {

    function testYnLSDdonationToZeroShareAttackResistance() public {

        uint INITIAL_AMOUNT = 10 ether;

        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        IERC20 assetToken = IERC20(chainAddresses.lsd.STETH_ADDRESS);

		// 1. Obtain stETH and Deposit assets to ynLSD by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        testAssetUtils.get_stETH(alice, INITIAL_AMOUNT);
        testAssetUtils.get_stETH(bob, INITIAL_AMOUNT);

        vm.prank(alice);
        assetToken.approve(address(ynlsd), type(uint256).max);

        vm.startPrank(bob);
        assetToken.approve(address(ynlsd), type(uint256).max);

        // Front-running part
        uint256 bobDepositAmount = INITIAL_AMOUNT / 2;
        // Alice knows that Bob is about to deposit INITIAL_AMOUNT*0.5 ATK to the Vault by observing the mempool
        vm.startPrank(alice);
        uint256 aliceDepositAmount = 1;
        uint256 aliceShares = ynlsd.deposit(assetToken, aliceDepositAmount, alice);
        // Since there are boostrap funds, this has no effect
        assertEq(compareWithThreshold(aliceShares, 1, 1), true, "Alice's shares should be dust"); 
        // Try to inflate shares value
        assetToken.transfer(address(ynlsd), bobDepositAmount);
        vm.stopPrank();

        // Check that Bob did not get 0 share when he deposits
        vm.prank(bob);
        uint256 bobShares = ynlsd.deposit(assetToken, bobDepositAmount, bob);

        assertGt(bobShares, 1 wei, "Bob's shares should be greater than 1 wei");
    }   
}