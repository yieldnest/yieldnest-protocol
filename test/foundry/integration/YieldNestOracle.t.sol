import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldNestOracleTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testSetAsset() public {
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);

        vm.expectRevert(bytes("ZeroAge"));
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(address(0), chainAddresses.RETH_FEED_ADDRESS, 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, address(0), 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(address(0), address(0), 0); // one hour
    }

    
    function testForGetLatestPrice() public {
        vm.expectRevert(bytes("Price feed not set"));
        yieldNestOracle.getLatestPrice(address(0));
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.RETH_FEED_ADDRESS);
        (, int256 price,, uint256 timeStamp,) = assetPriceFeed.latestRoundData();
        
        assertEq(timeStamp>0, true, "Zero timestamp");
        assertEq(price>0, true, "Zero price");
        // one hour age
        uint256 age = 1;
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, age);
        vm.expectRevert(
            abi.encodeWithSelector(PriceFeedTooStale.selector, block.timestamp - timeStamp, age)
        );
        yieldNestOracle.getLatestPrice(address(token));
        
        // 24 hours age
        age = 86400;
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, age);
        int256 obtainedPrice = yieldNestOracle.getLatestPrice(address(token));
        assertEq(price, obtainedPrice, "Price don't match");
    }
}