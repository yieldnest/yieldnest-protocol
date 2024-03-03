import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../../../src/external/chainlink/AggregatorV3Interface.sol";

contract YieldNestOracleTest is IntegrationBaseTest {
    // ContractAddresses contractAddresses = new ContractAddresses();
    // ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);
    function testSetAssetWithZeroAge() public {
        vm.expectRevert(YieldNestOracle.ZeroAge.selector);
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, 0); // zero age
    }

    function testSetAssetWithZeroAssetAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(address(0), chainAddresses.lsd.RETH_FEED_ADDRESS, 3600); // one hour, zero asset address
    }

    function testSetAssetWithZeroPriceFeedAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, address(0), 3600); // one hour, zero price feed address
    }

    function testSetAssetWithBothAddressesZero() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(address(0), address(0), 3600); // one hour, both addresses zero
    }

    function testSetAssetSuccessfully() public {
        address assetAddress = chainAddresses.lsd.RETH_ADDRESS;
        address priceFeedAddress = chainAddresses.lsd.RETH_FEED_ADDRESS;
        uint256 age = 3600; // one hour

        // Expect no revert, successful execution
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(assetAddress, priceFeedAddress, age);

        // Verify the asset price feed is set correctly
        (AggregatorV3Interface setPriceFeedAddress, uint256 setAge) = yieldNestOracle.assetPriceFeeds(assetAddress);
        assertEq(address(setPriceFeedAddress), priceFeedAddress, "Price feed address mismatch");
        assertEq(setAge, age, "Age mismatch");
    }
    
    function testForGetLatestPrice() public {

        IERC20 token = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.lsd.RETH_FEED_ADDRESS);
        (, int256 price, , uint256 timeStamp, ) = assetPriceFeed.latestRoundData();
        
        assertGt(timeStamp, 0, "Zero timestamp");
        assertGt(price, 0, "Zero price");
        // One hour age
        uint256 age = 1;
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, age);
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedTooStale.selector, block.timestamp - timeStamp, age)
        );
        yieldNestOracle.getLatestPrice(address(token));
        
        // 24 hours age
        age = 86400;
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.lsd.RETH_ADDRESS, chainAddresses.lsd.RETH_FEED_ADDRESS, age);
        uint256 obtainedPrice = yieldNestOracle.getLatestPrice(address(token));
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
        vm.prank(actors.ORACLE_MANAGER);
        yieldNestOracle.setAssetPriceFeed(assetAddress, newPriceFeedAddress, newAge);

        // Assert
        // Verify the asset price feed is updated correctly
        (AggregatorV3Interface updatedPriceFeedAddress, uint256 updatedAge) = yieldNestOracle.assetPriceFeeds(assetAddress);
        assertEq(address(updatedPriceFeedAddress), newPriceFeedAddress, "Price feed address not updated correctly");
        assertEq(updatedAge, newAge, "Age not updated correctly");
    }
}