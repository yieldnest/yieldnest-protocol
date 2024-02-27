import "./IntegrationBaseTest.sol";


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../src/external/chainlink/AggregatorV3Interface.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IPausable.sol";
// import "../../../src/mocks/MockERC20.sol";


contract ynLSDTest is IntegrationBaseTest {
    ContractAddresses contractAddresses = new ContractAddresses();
    ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testDepositSTETHFailingWhenStrategyIsPaused() public {
        IERC20 token = IERC20(chainAddresses.STETH_ADDRESS);
        uint256 amount = 1000;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();
        
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
        uint256 shares = ynlsd.deposit(token, amount, destination);
    }
    
    function testDepositSTETH() public {
        IERC20 token = IERC20(chainAddresses.STETH_ADDRESS);
        uint256 amount = 1000;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();
        
        address destination = address(this);
        // Obtain STETH from the biggest holder, deal does not work
        vm.startPrank(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        token.transfer(destination, amount+1);
        vm.stopPrank();
        uint balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);
        uint256 shares = ynlsd.deposit(token, amount, destination);

    }
    
    function testWrongStrategy() public {
        IERC20 token = IERC20(address(1));
        uint256 amount = 100;
        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(token)));
        uint256 shares = ynlsd.deposit(token, amount, address(this));
    }

    function testDepositWithZeroAmount() public {
        IERC20 token = IERC20(chainAddresses.STETH_ADDRESS);
        uint256 amount = 0; // Zero amount for deposit
        address receiver = address(this);

        vm.expectRevert(ynLSD.ZeroAmount.selector);
        ynlsd.deposit(token, amount, receiver);
    }

    
    function testGetSharesForToken() public {
        IERC20 token = IERC20(chainAddresses.RETH_ADDRESS);
        uint256 amount = 1000;
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.RETH_FEED_ADDRESS);

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
}