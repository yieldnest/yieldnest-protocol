import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../src/mocks/MockStrategyManager_v2.sol";
import "../../../src/mocks/MockStrategy.sol";
// import "../../../src/mocks/MockERC20.sol";

contract ynLSDTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    MockStrategy public mockStrategy1;
    MockStrategy public mockStrategy2;
    MockStrategyManager public mockStrategyManager;
    address[] public mockStrategies;
    

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
    
        mockStrategyManager = new MockStrategyManager();
        mockStrategy1 = new MockStrategy();
        mockStrategy1.setMultiplier(2);
        mockStrategy2 = new MockStrategy();
        mockStrategy2.setMultiplier(10);
        mockStrategies.push(address(mockStrategy1));
        mockStrategies.push(address(mockStrategy2));
        ynlsd.setStrategyManager(address(mockStrategyManager));
        ynlsd.setStrategies(tokens, mockStrategies);

        uint expectedEigenLayer = mockStrategy1.deposit(token, amount);
        // Check if event is emmitted
        vm.expectEmit();
        emit ynLSDEvents.Deposit(address(this), address(this), amount, expectedAmount, expectedEigenLayer);
        shares = ynlsd.deposit(token, amount);

    }
    function testSetStrategyManager() public {
        address newStrategyManager = address(new MockStrategyManager());
        ynlsd.setStrategyManager(newStrategyManager);
        assertEq(address(ynlsd.strategyManager()), newStrategyManager, "Strategy Manager not set correctly");
    }

    function testSetOracle() public {
        address newOracle = address(new YieldNestOracle());
        ynlsd.setOracle(newOracle);
        assertEq(address(ynlsd.oracle()), newOracle, "Oracle not set correctly");
    }

    function testSetStrategies() public {
        IERC20[] memory newTokens = new IERC20[](2);
        address[] memory newStrategies = new address[](2);
        newTokens[0] = IERC20(chainAddresses.RETH_ADDRESS);
        newTokens[1] = IERC20(chainAddresses.STETH_ADDRESS);
        newStrategies[0] = address(new MockStrategy());
        newStrategies[1] = address(new MockStrategy());
        ynlsd.setStrategies(newTokens, newStrategies);
        for(uint i = 0; i < newTokens.length; i++) {
            assertEq(address(ynlsd.strategies(newTokens[i])), newStrategies[i], "Strategy not set correctly for token");
        }
    }

    
    function testGetSharesForToken() public {
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        uint256 amount = 1000;

        // Call the getSharesForToken function
        uint256 shares = ynlsd.convertToShares(token, amount);
        // TODO to continue with it
        // obtaining the amount from a price feed to do the calculation

    }
}