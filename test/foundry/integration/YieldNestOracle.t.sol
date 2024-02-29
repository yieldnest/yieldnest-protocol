import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldNestOracleTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);
    function testSetAssetWithZeroAge() public {
        vm.expectRevert(YieldNestOracle.ZeroAge.selector);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, 0); // zero age
    }

    function testSetAssetWithZeroAssetAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        yieldNestOracle.setAssetPriceFeed(address(0), chainAddresses.RETH_FEED_ADDRESS, 3600); // one hour, zero asset address
    }

    function testSetAssetWithZeroPriceFeedAddress() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, address(0), 3600); // one hour, zero price feed address
    }

    function testSetAssetWithBothAddressesZero() public {
        vm.expectRevert(YieldNestOracle.ZeroAddress.selector);
        yieldNestOracle.setAssetPriceFeed(address(0), address(0), 3600); // one hour, both addresses zero
    }

    function testSetAssetSuccessfully() public {
        address assetAddress = chainAddresses.RETH_ADDRESS;
        address priceFeedAddress = chainAddresses.RETH_FEED_ADDRESS;
        uint256 age = 3600; // one hour

        // Expect no revert, successful execution
        yieldNestOracle.setAssetPriceFeed(assetAddress, priceFeedAddress, age);

        // Verify the asset price feed is set correctly
        (AggregatorV3Interface setPriceFeedAddress, uint256 setAge) = yieldNestOracle.assetPriceFeeds(assetAddress);
        assertEq(address(setPriceFeedAddress), priceFeedAddress, "Price feed address mismatch");
        assertEq(setAge, age, "Age mismatch");
    }
    
    function testForGetLatestPrice() public {
        vm.expectRevert(bytes("Price feed not set"));
        yieldNestOracle.getLatestPrice(address(0));

        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.RETH_FEED_ADDRESS);
        (, int256 price, , uint256 timeStamp, ) = assetPriceFeed.latestRoundData();
        
        assertEq(timeStamp > 0, true, "Zero timestamp");
        assertEq(price > 0, true, "Zero price");

        // One hour age
        uint256 age = 1;
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, age);
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedTooStale.selector, block.timestamp - timeStamp, age)
        );
        yieldNestOracle.getLatestPrice(address(token));
        
        // 24 hours age
        age = 86400;
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, age);
        uint256 obtainedPrice = yieldNestOracle.getLatestPrice(address(token));
        assertEq(uint256(price), obtainedPrice, "Price mismatch");
    }
}