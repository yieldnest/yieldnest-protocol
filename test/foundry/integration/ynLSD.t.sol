import "./IntegrationBaseTest.sol";


import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../src/external/chainlink/AggregatorV3Interface.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IPausable.sol";
import {ILSDStakingNode} from "../../../src/interfaces/ILSDStakingNode.sol";
// import "../../../src/mocks/MockERC20.sol";

import "../mocks/TestLSDStakingNodeV2.sol";
import "../mocks/TestYnLSDV2.sol";



contract ynLSDTest is IntegrationBaseTest {
    // ContractAddresses contractAddresses = new ContractAddresses();
    // ContractAddresses.ChainAddresses public chainAddresses = contractAddresses.getChainAddresses(block.chainid);
    error PriceFeedTooStale(uint256 age, uint256 maxAge);

    function testDepositSTETHFailingWhenStrategyIsPaused() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();
        
        address destination = address(this);
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        //token.transfer(destination, amount + 1);
        vm.stopPrank();
        uint balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");

        token.approve(address(ynlsd), amount);
        uint256 shares = ynlsd.deposit(token, amount, destination);

        IERC20[] memory assets = new IERC20[](1);
        uint[] memory amounts = new uint[](1);
        assets[0] = token;
        amounts[0] = amount;

        vm.expectRevert(bytes("Pausable: index is paused"));
        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }
    
    function testDepositSTETH() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();
        
        address destination = address(this);
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);
        uint256 shares = ynlsd.deposit(token, amount, destination);

        IERC20[] memory assets = new IERC20[](1);
        uint[] memory amounts = new uint[](1);
        assets[0] = token;
        amounts[0] = amount;

        lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
    }
    
    function testWrongStrategy() public {
        IERC20 token = IERC20(address(1));
        uint256 amount = 100;
        vm.expectRevert(abi.encodeWithSelector(ynLSD.UnsupportedAsset.selector, address(token)));
        uint256 shares = ynlsd.deposit(token, amount, address(this));
    }

    function testDepositWithZeroAmount() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 0; // Zero amount for deposit
        address receiver = address(this);

        vm.expectRevert(ynLSD.ZeroAmount.selector);
        ynlsd.deposit(token, amount, receiver);
    }

    
    function testGetSharesForToken() public {
        IERC20 token = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;
        AggregatorV3Interface assetPriceFeed = AggregatorV3Interface(chainAddresses.lsd.RETH_FEED_ADDRESS);

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

    function testTotalAssetsAfterDeposit() public {
        IERC20 token = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        uint256 expectedAmount = ynlsd.convertToShares(token, amount);

        IPausable pausableStrategyManager = IPausable(address(strategyManager));

        ILSDStakingNode lsdStakingNode = ynlsd.createLSDStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();
        
        address destination = address(this);
        // Obtain STETH 
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint balance = token.balanceOf(address(this));
        emit log_uint(balance);
        assertEq(balance, amount, "Amount not received");
        token.approve(address(ynlsd), amount);
        uint256 shares = ynlsd.deposit(token, amount, destination);

        {
            IERC20[] memory assets = new IERC20[](1);
            uint[] memory amounts = new uint[](1);
            assets[0] = token;
            amounts[0] = amount;

            lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
        }

        uint256 totalAssetsAfterDeposit = ynlsd.totalAssets();

        uint256 oraclePrice = yieldNestOracle.getLatestPrice(address(token));

        IStrategy strategy = ynlsd.strategies(IERC20(chainAddresses.lsd.STETH_ADDRESS));
        uint256 balanceInStrategyForNode  = strategy.userUnderlyingView((address(lsdStakingNode)));

        uint expectedBalance = balanceInStrategyForNode * oraclePrice / 1e18;

        // Assert that totalAssets reflects the deposit
        assertEq(totalAssetsAfterDeposit, expectedBalance, "Total assets do not reflect the deposit");
    }

    function testCreateLSDStakingNode() public {
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        uint expectedNodeId = 0;
        assertEq(lsdStakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreate2LSDStakingNodes() public {
        ILSDStakingNode lsdStakingNodeInstance1 = ynlsd.createLSDStakingNode();
        uint expectedNodeId1 = 0;
        assertEq(lsdStakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        ILSDStakingNode lsdStakingNodeInstance2 = ynlsd.createLSDStakingNode();
        uint expectedNodeId2 = 1;
        assertEq(lsdStakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

    function testCreateLSDStakingNodeAfterUpgradeWithoutUpgradeability() public {
        // Upgrade the ynLSD implementation to TestYnLSDV2
        address newImplementation = address(new TestYnLSDV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newImplementation, "");

        // Attempt to create a LSD staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        ynlsd.createLSDStakingNode();
    }

    function testUpgradeLSDStakingNodeImplementation() public {
        ILSDStakingNode lsdStakingNodeInstance = ynlsd.createLSDStakingNode();

        // upgrade the ynLSD to support the new initialization version.
        address newYnLSDImpl = address(new TestYnLSDV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(ynlsd)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynlsd)), newYnLSDImpl, "");

        TestLSDStakingNodeV2 testLSDStakingNodeV2 = new TestLSDStakingNodeV2();
        ynlsd.upgradeLSDStakingNodeImplementation(address(testLSDStakingNodeV2));

        UpgradeableBeacon beacon = ynlsd.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, address(testLSDStakingNodeV2));

        TestLSDStakingNodeV2 testLSDStakingNodeV2Instance = TestLSDStakingNodeV2(payable(address(lsdStakingNodeInstance)));
        uint redundantFunctionResult = testLSDStakingNodeV2Instance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(testLSDStakingNodeV2Instance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testFailRegisterLSDStakingNodeImplementationTwice() public {
        address initialImplementation = address(new TestLSDStakingNodeV2());
        ynlsd.registerLSDStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new TestLSDStakingNodeV2());
        vm.expectRevert("ynLSD: Implementation already exists");
        ynlsd.registerLSDStakingNodeImplementationContract(newImplementation);
    }
}