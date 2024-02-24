import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../src/mocks/MockStrategyManager_v2.sol";
import "../../../src/mocks/MockStrategy.sol";
import "../../../src/interfaces/chainlink/AggregatorV3Interface.sol";
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

    function testDepositSTETH() public {
        IERC20 token = IERC20(chainAddresses.STETH_ADDRESS);
        uint256 amount = 1000;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);
        
        vm.expectRevert(bytes("ALLOWANCE_EXCEEDED"));
        uint256 shares = ynlsd.deposit(token, amount);
        address destination = address(this);
        // Obtain STETH from the biggest holder, deal does not work
        vm.startPrank(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        token.transfer(destination, amount+1);
        vm.stopPrank();
        uint balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);
        vm.expectRevert(bytes("Pausable: index is paused"));
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
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.RETH_FEED_ADDRESS);
        // Call the getSharesForToken function
        uint256 shares = ynlsd.convertToShares(token, amount);
        (, int256 price,, uint256 timeStamp,) = assetPriceFeed.latestRoundData();

        assertEq(ynlsd.totalAssets(), 0);
        assertEq(ynlsd.totalSupply(), 0);

        assertEq(timeStamp>0, true, "Zero timestamp");
        assertEq(price>0, true, "Zero price");
        assertEq(block.timestamp - timeStamp < 86400, true, "Price stale for more than 24 hours");
        assertEq(shares, (uint256(price)*amount)/1e18, "Total shares don't match");
        
    }
}