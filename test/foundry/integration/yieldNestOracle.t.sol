import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ynLSDTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testSetAsset() public {
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        uint256 amount = 1000;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        vm.expectRevert(bytes("ZeroAge"));
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, chainAddresses.RETH_FEED_ADDRESS, 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(address(0), chainAddresses.RETH_FEED_ADDRESS, 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(chainAddresses.RETH_ADDRESS, address(0), 0); // one hour
        vm.expectRevert(bytes("ZeroAddress"));
        yieldNestOracle.setAssetPriceFeed(address(0), address(0), 0); // one hour
    }

    
    function testGetSharesForToken() public {
        // Define the token and amount
        // IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        // uint256 amount = 1000;

        // // Call the getSharesForToken function
        // uint256 shares = ynlsd.convertToShares(token, amount);

        // // Get the expected shares from the external view function
        // uint256 expectedShares = ynlsd.getExpectedShares(token, amount);

        // // Assert that the shares are as expected
        // assertEq(shares, expectedShares);
    }
}