// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./IntegrationBaseTest.sol";


import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../../../src/external/chainlink/AggregatorV3Interface.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IPausable.sol";
import {ILSDStakingNode} from "../../../src/interfaces/ILSDStakingNode.sol";
import {TestLSDStakingNodeV2} from "../mocks/TestLSDStakingNodeV2.sol";
import {TestYnLSDV2} from "../mocks/TestYnLSDV2.sol";
import {ynBase} from "../../../src/ynBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/Console.sol";

contract ynLSDTest is IntegrationBaseTest {
    // ContractAddresses contractAddresses = new ContractAddresses();
    // ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testDepositSTETHFailingWhenStrategyIsPaused() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();
        
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        //token.transfer(destination, amount + 1);
        vm.stopPrank();
        uint256 balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");

        token.approve(address(ynlsd), amount);

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = token;
        amounts[0] = amount;

        vm.expectRevert(bytes("Pausable: index is paused"));
        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }
    
    function testDepositSTETH() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();
        
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = token;
        amounts[0] = amount;

        vm.prank(actors.LSD_RESTAKING_MANAGER);
        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }
    
    function testWrongStrategy() public {
        IERC20 token = IERC20(address(1));
        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(token)));
    }

    function testDepositWithZeroAmount() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 0; // Zero amount for deposit
        address receiver = address(this);

        vm.expectRevert(ynLSD.ZeroAmount.selector);
        ynlsd.deposit(token, amount, receiver);
    }

    
    function testGetSharesForToken() public {
        IERC20 token = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.lsd.RETH_FEED_ADDRESS);

        // Call the getSharesForToken function
        uint256 shares = ynlsd.convertToShares(token, amount);
        (, int256 price, , uint256 timeStamp, ) = assetPriceFeed.latestRoundData();

        assertEq(ynlsd.totalAssets(), 0);
        assertEq(ynlsd.totalSupply(), 0);

        assertEq(timeStamp > 0, true, "Zero timestamp");
        assertEq(price > 0, true, "Zero price");
        assertEq(block.timestamp - timeStamp < 86400, true, "Price stale for more than 24 hours");
        assertEq(shares, (uint256(price) * amount) / 1e18, "Total shares don't match");
    }

    function testTotalAssetsAfterDeposit() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;

        IPausable pausableStrategyManager = IPausable(address(strategyManager));
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();
        
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);

        {
            IERC20[] memory assets = new IERC20[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = token;
            amounts[0] = amount;

            vm.prank(actors.LSD_RESTAKING_MANAGER);
            lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
        }

        uint256 totalAssetsAfterDeposit = ynlsd.totalAssets();

        uint256 oraclePrice = yieldNestOracle.getLatestPrice(address(token));

        IStrategy strategy = ynlsd.strategies(IERC20(chainAddresses.lsd.STETH_ADDRESS));
        uint256 balanceInStrategyForNode  = strategy.userUnderlyingView((address(lsdStakingNode)));

        uint256 expectedBalance = balanceInStrategyForNode * oraclePrice / 1e18;

        // Assert that totalAssets reflects the deposit
        assertEq(totalAssetsAfterDeposit, expectedBalance, "Total assets do not reflect the deposit");
    }
    function testCreateLSDStakingNode() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        uint256 expectedNodeId = 0;
        assertEq(lsdStakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
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

    function testDespositUnsupportedAsset() public {
        IERC20 token = IERC20(address(1));
        uint256 amount = 1 ether;
        address receiver = address(this);

        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(token)));
        ynlsd.deposit(token, amount, receiver);
    }

    function testDepositConvertToSharesMath() public {
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 128 ether;

        // Obtain STETH
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
        assertEq(balance, amount, "Amount not received");
        stETH.approve(address(ynlsd), amount);

        // vm.startPrank(user);
        stETH.approve(address(ynlsd), 100 ether);
        ynlsd.deposit(stETH, 32 ether, address(this));
        ynlsd.deposit(stETH, 32 ether, address(this));
        ynlsd.deposit(stETH, 32 ether, address(this));
        // vm.stopPrank();

        // ynlsd.totalSupply();

        // uint16 BASIS_POINTS_DENOMINATOR = 10_000;


        // // console.log("%i", ynlsd.totalSupply() * uint256(BASIS_POINTS_DENOMINATOR - ynlsd.exchangeAdjustmentRate()));
        // console.log("%i", ynlsd.totalSupply());
        ynlsd.totalAssets();
        (uint256[] memory assetBalances) = ynlsd.getTotalAssets();
        console.log("%i", assetBalances[0]);


        // uint256 result = Math.mulDiv(
        //     32 ether,
        //     ynlsd.totalSupply() * (uint256(BASIS_POINTS_DENOMINATOR) - ynlsd.exchangeAdjustmentRate()),
        //     ynlsd.totalSupply() * uint256(BASIS_POINTS_DENOMINATOR),
        //     Math.Rounding.Ceil
        // );

        // console.log("%i", result);
 
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
        bool isWhitelisted = ynlsd.isAddressWhitelisted(actors.TRANSFER_ENABLED_EOA);
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
        bool isFirstAddressWhitelisted = ynlsd.isAddressWhitelisted(newWhitelistAddresses[0]);
        bool isSecondAddressWhitelisted = ynlsd.isAddressWhitelisted(newWhitelistAddresses[1]);
        assertFalse(isFirstAddressWhitelisted, "First new whitelist address was not removed");
        assertFalse(isSecondAddressWhitelisted, "Second new whitelist address was not removed");
    }
}