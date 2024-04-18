// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "test/integration/IntegrationBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "src/external/chainlink/AggregatorV3Interface.sol";


contract YieldNestOracleTest is IntegrationBaseTest {

    error PriceFeedTooStale(uint256 age, uint256 maxAge);
    function testSetAssetWithZeroAge() public {
        vm.expectRevert(YieldNestOracle.ZeroAge.selector);
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, 0); // zero age
    }

    function testSetAssetWithZeroAssetAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(address(0), chainAddresses.lsd.RETH_FEED_ADDRESS, 3600); // one hour, zero asset address
    }

    function testSetAssetWithZeroPriceFeedAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, address(0), 3600); // one hour, zero price feed address
    }

    function testSetAssetWithBothAddressesZero() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(address(0), address(0), 3600); // one hour, both addresses zero
    }

    function testSetAssetSuccessfully() public {
        address assetAddress = chainAddresses.lsd.RETH_ADDRESS;
        address priceFeedAddress = chainAddresses.lsd.RETH_FEED_ADDRESS;
        uint256 age = 3600; // one hour

        // Expect no revert, successful execution
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(assetAddress, priceFeedAddress, age);

        // Verify the asset price feed is set correctly
        (AggregatorV3Interface setPriceFeedAddress, uint256 setAge) = yieldNestOracle.assetPriceFeeds(assetAddress);
        assertEq(address(setPriceFeedAddress), priceFeedAddress, "Price feed address mismatch");
        assertEq(setAge, age, "Age mismatch");
    }
    
    function testForGetLatestPrice() public {

        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.lsd.RETH_FEED_ADDRESS);
        (, int256 price, , uint256 timeStamp, ) = assetPriceFeed.latestRoundData();
        
        assertGt(timeStamp, 0, "Zero timestamp");
        assertGt(price, 0, "Zero price");
        // One hour age
        uint256 age = 1;
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, age);
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedTooStale.selector, block.timestamp - timeStamp, age)
        );
        yieldNestOracle.getLatestPrice(address(asset));
        
        // 24 hours age
        age = 86400;
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, age);
        uint256 obtainedPrice = yieldNestOracle.getLatestPrice(address(asset));
        assertEq(uint256(price), obtainedPrice, "Price mismatch");
    }

    function testGetLatestPriceWithUnsetAsset() public {
        // Arrange
        address unsetAssetAddress = address(1); // An arbitrary address not set in the oracle

        // Act & Assert
        // Expect the oracle to revert with "Price feed not set" for an asset that hasn't been set up
        vm.expectRevert(abi.encodeWithSelector(YieldNestOracle.PriceFeedNotSet.selector));
        yieldNestOracle.getLatestPrice(unsetAssetAddress);
    }

    function testUpdateAssetPriceFeedSuccessfully() public {
        // Arrange
        address assetAddress = chainAddresses.lsd.RETH_ADDRESS;
        address newPriceFeedAddress = address(2); // An arbitrary new price feed address
        uint256 newAge = 7200; // two hours

        // Act
        vm.prank(actors.admin.ORACLE_ADMIN);
        yieldNestOracle.setAssetPriceFeed(assetAddress, newPriceFeedAddress, newAge);

        // Assert
        // Verify the asset price feed is updated correctly
        (AggregatorV3Interface updatedPriceFeedAddress, uint256 updatedAge) = yieldNestOracle.assetPriceFeeds(assetAddress);
        assertEq(address(updatedPriceFeedAddress), newPriceFeedAddress, "Price feed address not updated correctly");
        assertEq(updatedAge, newAge, "Age not updated correctly");
    }

    function setupIntializationTests(address[] memory assetAddresses, address[] memory priceFeeds, uint256[] memory maxAges) 
        public returns (YieldNestOracle, YieldNestOracle.Init memory) {
        TransparentUpgradeableProxy yieldNestOracleProxy;
        yieldNestOracle = new YieldNestOracle();
        yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracle), actors.admin.PROXY_ADMIN_OWNER, "");
        yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));

        IStrategy[] memory strategies = new IStrategy[](2);
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;

        strategies[0] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);
        strategies[1] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);

        YieldNestOracle.Init memory oracleInit = YieldNestOracle.Init({
            assets: assetAddresses,
            priceFeedAddresses: priceFeeds,
            maxAges: maxAges,
            admin: actors.admin.ADMIN,
            oracleManager: actors.admin.ORACLE_ADMIN
        });
        return (yieldNestOracle, oracleInit);
    }

    function testInitializeAssetAddressesArraysLengthMismatch() public {
        address[] memory assetAddresses = new address[](3);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);

        assetAddresses[0] = chainAddresses.lsd.RETH_ADDRESS;
        assetAddresses[1] = chainAddresses.lsd.STETH_ADDRESS;
        assetAddresses[2] = chainAddresses.lsd.STETH_ADDRESS;
        priceFeeds[0] = chainAddresses.lsd.RETH_FEED_ADDRESS;
        priceFeeds[1] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[1] = uint256(86400);
        maxAges[0] = uint256(86400);

       (YieldNestOracle oracle, YieldNestOracle.Init memory init) = setupIntializationTests(assetAddresses, priceFeeds, maxAges);
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldNestOracle.ArraysLengthMismatch.selector,
                assetAddresses.length,
                priceFeeds.length,
                maxAges.length
            )
        );
        oracle.initialize(init);
    }

    function testInitializeAssetMaxAgesLengthMismatch() public {
        address[] memory assetAddresses = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](3);

        assetAddresses[0] = chainAddresses.lsd.RETH_ADDRESS;
        assetAddresses[1] = chainAddresses.lsd.STETH_ADDRESS;

        priceFeeds[0] = chainAddresses.lsd.RETH_FEED_ADDRESS;
        priceFeeds[1] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[0] = uint256(86400);
        maxAges[1] = uint256(86400);
        maxAges[2] = uint256(86400);

       (YieldNestOracle oracle, YieldNestOracle.Init memory init) = setupIntializationTests(assetAddresses, priceFeeds, maxAges);
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldNestOracle.ArraysLengthMismatch.selector,
                assetAddresses.length,
                priceFeeds.length,
                maxAges.length
            )
        );
        oracle.initialize(init);
    }

    function testInitializePriceFeedZeroAddress() public {
        address[] memory assetAddresses = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        assetAddresses[0] = chainAddresses.lsd.RETH_ADDRESS;
        assetAddresses[1] = chainAddresses.lsd.STETH_ADDRESS;
        priceFeeds[0] = address(0);
        priceFeeds[1] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[0] = uint256(86400);
        maxAges[1] = uint256(86400);

       (YieldNestOracle oracle, YieldNestOracle.Init memory init) = setupIntializationTests(assetAddresses, priceFeeds, maxAges);
        vm.expectRevert(abi.encodeWithSelector(YieldNestOracle.ZeroAddress.selector));
        oracle.initialize(init);
    }

    function testInitializeAssetZeroAddress() public {
        address[] memory assets = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        assets[0] = address(0);
        assets[1] = address(0);
        priceFeeds[0] = chainAddresses.lsd.RETH_FEED_ADDRESS;
        priceFeeds[1] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[0] = uint256(86400);
        maxAges[1] = uint256(86400);

       (YieldNestOracle oracle, YieldNestOracle.Init memory init) = setupIntializationTests(assets, priceFeeds, maxAges);
        vm.expectRevert(abi.encodeWithSelector(YieldNestOracle.ZeroAddress.selector));
        oracle.initialize(init);
    }    
}

