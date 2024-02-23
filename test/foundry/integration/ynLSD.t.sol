import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "../../../src/mocks/MockERC20.sol";

contract ynLSDTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testDeposit() public {
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        uint256 amount = 1000;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);
        
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        uint256 shares = ynlsd.deposit(token, amount);
        deal(address(token), address(this), amount);
        token.approve(address(ynlsd), amount);
        vm.expectRevert(bytes("Pausable: index is paused"));
        shares = ynlsd.deposit(token, amount);

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