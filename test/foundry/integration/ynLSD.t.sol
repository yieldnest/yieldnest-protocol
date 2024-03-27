// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./IntegrationBaseTest.sol";


import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "src/external/chainlink/AggregatorV3Interface.sol";
import {IPausable} from "src/external/eigenlayer/v0.1.0/interfaces//IPausable.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {TestLSDStakingNodeV2} from "test/foundry/mocks/TestLSDStakingNodeV2.sol";
import {TestYnLSDV2} from "test/foundry/mocks/TestYnLSDV2.sol";
import {ynBase} from "src/ynBase.sol";

contract ynLSDAssetTest is IntegrationBaseTest {
    function testDepositSTETHFailingWhenStrategyIsPaused() public {
        IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();
        
        // Obtain STETH

        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        assertEq(compareWithThreshold(asset.balanceOf(address(this)), amount, 1), true, "Amount not received");
        vm.stopPrank();

        asset.approve(address(ynlsd), amount);

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = amount;

        vm.expectRevert(bytes("Pausable: index is paused"));
        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }

    function testDepositSTETHSuccessWithOneDeposit() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 32 ether;

        uint256 initialSupply = ynlsd.totalSupply();
        uint256 initialTotalAssets = ynlsd.totalAssets();

        // Obtain STETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
        assertEq(compareWithThreshold(balance, amount, 1), true, "Amount not received");

        uint depositAmount = 15 ether;

        stETH.approve(address(ynlsd), 32 ether);
        ynlsd.deposit(stETH, depositAmount, address(this));

        assertEq(ynlsd.balanceOf(address(this)), ynlsd.totalSupply() - initialSupply, "ynlsd balance does not match total supply");
        assertTrue((depositAmount - (ynlsd.totalAssets() - initialTotalAssets)) < 1e18, "Total assets do not match user deposits");
        assertTrue((depositAmount - ynlsd.balanceOf(address(this))) < 1e18, "Invalid ynLSD Balance");
    }
    
    function testDepositSTETHSuccessWithMultipleDeposits() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 32 ether;

        uint256 initialSupply = ynlsd.totalSupply();
        uint256 initialTotalAssets = ynlsd.totalAssets();

        // Obtain STETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
        assertEq(compareWithThreshold(balance, amount, 1), true, "Amount not received");

        stETH.approve(address(ynlsd), 32 ether);
        uint256 depositAmountOne = 5 ether;
        uint256 depositAmountTwo = 3 ether;
        uint256 depositAmountThree = 7 ether;

        ynlsd.deposit(stETH, depositAmountOne, address(this));
        ynlsd.deposit(stETH, depositAmountTwo, address(this));
        ynlsd.deposit(stETH, depositAmountThree, address(this));

        uint256 totalDeposit = depositAmountOne + depositAmountTwo + depositAmountThree;

        assertEq(ynlsd.balanceOf(address(this)), ynlsd.totalSupply() - initialSupply, "ynlsd balance does not match total supply");
        assertTrue((totalDeposit - (ynlsd.totalAssets() - initialTotalAssets)) < 1e18, "Total assets do not match user deposits");
        assertTrue(totalDeposit - ynlsd.balanceOf(address(this)) < 1e18, "Invalid ynLSD Balance");
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
        vm.prank(actors.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
        uint256[] memory totalAssets = ynlsd.getTotalAssets();
        ynlsd.nodes(0);
        
        uint256 bootstrapAmountUnits = ynlsd.BOOTSTRAP_AMOUNT_UNITS() * 1e18 - 1;
        assertTrue(compareWithThreshold(totalAssets[0], bootstrapAmountUnits, 1), "Total assets should be equal to bootstrap amount");
    }

    function testConvertToSharesZeroStrategy() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
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
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

        uint256 totalAssetsBeforeDeposit = ynlsd.totalAssets();
        
        // Obtain STETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = asset.balanceOf(address(this));
        assertEq(compareWithThreshold(balance, amount, 1), true, "Amount not received");
        asset.approve(address(ynlsd), amount);
        ynlsd.deposit(asset, amount, address(this));


        {
            IERC20[] memory assets = new IERC20[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = asset;
            amounts[0] = amount;

            vm.prank(actors.LSD_RESTAKING_MANAGER);

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
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        uint256 expectedNodeId = 0;
        assertEq(lsdStakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreateStakingNodeLSDOverMax() public {
        vm.startPrank(actors.STAKING_NODE_CREATOR);
        for (uint256 i = 0; i < 10; i++) {
            ynlsd.createLSDStakingNode();
        }
        vm.expectRevert(abi.encodeWithSelector(ynLSD.TooManyStakingNodes.selector, 10));
        ynlsd.createLSDStakingNode();
        vm.stopPrank();
    } 

    function testCreate2LSDStakingNodes() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance1 = ynlsd.createLSDStakingNode();
        uint256 expectedNodeId1 = 0;
        assertEq(lsdStakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance2 = ynlsd.createLSDStakingNode();
        uint256 expectedNodeId2 = 1;
        assertEq(lsdStakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

    function testCreateLSDStakingNodeAfterUpgradeWithoutUpgradeability() public {
        // Upgrade the ynLSD implementation to TestYnLSDV2
        address newImplementation = address(new TestYnLSDV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newImplementation, "");

        // Attempt to create a LSD staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        vm.prank(actors.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();
    }

    function testUpgradeLSDStakingNodeImplementation() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        // upgrade the ynLSD to support the new initialization version.
        address newYnLSDImpl = address(new TestYnLSDV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newYnLSDImpl, "");

        TestLSDStakingNodeV2 testLSDStakingNodeV2 = new TestLSDStakingNodeV2();
        vm.prank(actors.STAKING_ADMIN);
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

        vm.prank(actors.STAKING_NODE_CREATOR);
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

        vm.prank(actors.STAKING_NODE_CREATOR);
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

        vm.prank(actors.STAKING_NODE_CREATOR);
        ynlsd.createLSDStakingNode();

        ILSDStakingNode lsdStakingNode = ynlsd.nodes(0);
        vm.deal(address(lsdStakingNode), 1000);

        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = asset.balanceOf(address(this));
        assertEq(compareWithThreshold(balance, amount, 1), true, "Amount not received");

        asset.approve(address(ynlsd), amount);
        ynlsd.deposit(asset, amount, address(this));

        vm.startPrank(address(lsdStakingNode));
        asset.approve(address(ynlsd), 32 ether);
        ynlsd.retrieveAsset(0, asset, amount);
        vm.stopPrank();
    }

    function testSetMaxNodeCount() public {
        uint256 maxNodeCount = 10;
        vm.prank(actors.STAKING_ADMIN);
        ynlsd.setMaxNodeCount(maxNodeCount);
        assertEq(ynlsd.maxNodeCount(), maxNodeCount, "Max node count does not match expected value");
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
        address whitelistedAddress = actors.TRANSFER_ENABLED_EOA; // Using the pre-defined whitelisted address from setup
        address recipient = address(6); // An arbitrary recipient address

        // get stETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: depositAmount + 1}("");
        require(success, "ETH transfer failed");

        IERC20 steth = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        steth.approve(address(ynlsd), depositAmount);
        ynlsd.deposit(steth, depositAmount, whitelistedAddress); 

        uint256 transferAmount = ynlsd.balanceOf(whitelistedAddress);

        // Act
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedAddress;
        vm.prank(actors.PAUSE_ADMIN);
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
        vm.prank(actors.PAUSE_ADMIN);
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

         // get stETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: depositAmount + 1}("");
        require(success, "ETH transfer failed");

        IERC20 steth = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        steth.approve(address(ynlsd), depositAmount);
        ynlsd.deposit(steth, depositAmount, newWhitelistedAddress);

        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = newWhitelistedAddress;
        vm.prank(actors.PAUSE_ADMIN);
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

         // get stETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: depositAmount + 1}("");
        require(success, "ETH transfer failed");
        IERC20 steth = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        steth.approve(address(ynlsd), depositAmount);
        ynlsd.deposit(steth, depositAmount, arbitraryAddress);

        uint256 transferAmount = ynlsd.balanceOf(arbitraryAddress);

        // Act
        vm.prank(actors.PAUSE_ADMIN);
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
        whitelistAddresses[0] = actors.TRANSFER_ENABLED_EOA; // EOA address to be removed from whitelist

        // Act
        vm.prank(actors.PAUSE_ADMIN);
        ynlsd.removeFromPauseWhitelist(whitelistAddresses); // Removing the EOA address from whitelist

        // Assert
        bool isWhitelisted = ynlsd.pauseWhiteList(actors.TRANSFER_ENABLED_EOA);
        assertFalse(isWhitelisted, "EOA address was not removed from whitelist");
    }

    function testRemoveMultipleNewWhitelistAddresses() public {
        // Arrange
        address[] memory newWhitelistAddresses = new address[](2);
        newWhitelistAddresses[0] = address(20000); // First new whitelist address
        newWhitelistAddresses[1] = address(20001); // Second new whitelist address

        // Adding addresses to whitelist first
        vm.prank(actors.PAUSE_ADMIN);
        ynlsd.addToPauseWhitelist(newWhitelistAddresses);

        // Act
        vm.prank(actors.PAUSE_ADMIN);
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

        uint INITIAL_AMOUNT = 10_000 ether;

        address _alice = makeAddr("Alice");
        address _bob = makeAddr("Bob");

        IERC20 assetToken = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        vm.deal(_alice, INITIAL_AMOUNT);
        vm.deal(_bob, INITIAL_AMOUNT);


        IERC20 steth = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        // get stETH
         vm.startPrank(_alice);
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: INITIAL_AMOUNT}("");
        require(success, "ETH transfer failed");

        steth.approve(address(ynlsd), type(uint256).max);

        vm.startPrank(_bob);
        (success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: INITIAL_AMOUNT}("");
        require(success, "ETH transfer failed");

        steth.approve(address(ynlsd), type(uint256).max);

        // Front-running part
        uint256 bobDepositAmount = INITIAL_AMOUNT / 2;
        // Alice knows that Bob is about to deposit INITIAL_AMOUNT*0.5 ATK to the Vault by observing the mempool
        vm.startPrank(_alice);
        uint256 aliceDepositAmount = 1;
        uint256 aliceShares = ynlsd.deposit(assetToken, aliceDepositAmount, _alice);
        assertEq(aliceShares, 0); // Since there are boostrap funds, this has no effect
        // Try to inflate shares value
        assetToken.transfer(address(ynlsd), bobDepositAmount);
        vm.stopPrank();

        // Check that Bob did not get 0 share when he deposits
        vm.prank(_bob);
        uint256 bobShares = ynlsd.deposit(assetToken, bobDepositAmount, _bob);

        assertGt(bobShares, 1 wei, "Bob's shares should be greater than 1 wei");
    }   
}