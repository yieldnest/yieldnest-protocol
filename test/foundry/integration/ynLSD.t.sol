import "forge-std/Test.sol";
import "../../../src/ynLSD.sol";
import "../../../src/YieldNestOracle.sol";
import "../../../src/interfaces/eigenlayer/IStrategy.sol";;
import "../../../src/mocks/MockStrategyManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ynLSDTest is Test {
    ynLSD public ynlsd;
    YieldNestOracle public yieldNestOracle;



    function setUp() public {
        // Initialize the contract with appropriate values
        ynLSD.Init memory init;
        // Fill the init struct with appropriate values
        ynlsd = new ynLSD();
        ynlsd.initialize(init);
    }

    function testDeposit() public {
        // IERC20 token;
        // uint256 amount;
        // uint256 minExpectedAmountOfShares;

        // minExpectedAmountOfShares = ynlsd.getExpectedShares(token, amount, minExpectedAmountOfShares);
        // uint256 shares = ynlsd.deposit(token, amount, minExpectedAmountOfShares);
        // assertEq(shares, minExpectedAmountOfShares);
    }

    function testDepositOnBehalf() public {
        // // Define the token, receiver, amount, and minExpectedAmountOfShares
        // IERC20 token;
        // address receiver;
        // uint256 amount;
        // uint256 minExpectedAmountOfShares;

        // // Call the depositOnBehalf function
        // uint256 shares = ynlsd.depositOnBehalf(token, receiver, amount, minExpectedAmountOfShares);

        // // Get the expected shares from the external view function
        // uint256 expectedShares = ynlsd.getExpectedShares(token, receiver, amount, minExpectedAmountOfShares);

        // // Assert that the shares received are as expected
        // assertEq(shares, expectedShares);
    }

    function testGetSharesForToken() public {
        // // Define the token and amount
        // IERC20 token;
        // uint256 amount;

        // // Call the getSharesForToken function
        // uint256 shares = ynlsd.getSharesForToken(token, amount);

        // // Get the expected shares from the external view function
        // uint256 expectedShares = ynlsd.getExpectedShares(token, amount);

        // // Assert that the shares are as expected
        // assertEq(shares, expectedShares);
    }
}