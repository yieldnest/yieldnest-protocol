// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {AggregatorV3Interface} from "src/external/chainlink/AggregatorV3Interface.sol";

interface IYieldNestOracleEvents {
    event AssetPriceFeedSet(address indexed asset, address indexed priceFeedAddress, uint256 maxAge);
}

contract YieldNestOracle is AccessControlUpgradeable, IYieldNestOracleEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------
    
    error PriceFeedTooStale(uint256 age, uint256 maxAge);
    error ZeroAddress();
    error ZeroAge();
    error ArraysLengthMismatch(uint256 assetsLength, uint256 priceFeedAddressesLength, uint256 maxAgesLength);
    error PriceFeedNotSet();
    error InvalidPriceValue(int256 price); 
    
    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    struct AssetPriceFeed {
        AggregatorV3Interface priceFeed;
        uint256 maxAge; // in seconds
    }

    mapping(address => AssetPriceFeed) public assetPriceFeeds;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------
    
    struct Init {
        address[] assets;
        address[] priceFeedAddresses;
        uint256[] maxAges;
        address admin;
        address oracleManager;
    }

    constructor() {
       _disableInitializers();
    }

    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.oracleManager)
        initializer {
         __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(ORACLE_MANAGER_ROLE, init.oracleManager);

        if (init.assets.length != init.priceFeedAddresses.length || init.assets.length != init.maxAges.length) {
            revert ArraysLengthMismatch({assetsLength: init.assets.length, priceFeedAddressesLength: init.priceFeedAddresses.length, maxAgesLength: init.maxAges.length});
        }
        for (uint256 i = 0; i < init.assets.length; i++) {
            _setAssetPriceFeed(init.assets[i], init.priceFeedAddresses[i], init.maxAges[i]);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  FUNCTIONS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Sets the price feed for a given asset.
     * @param asset The address of the asset.
     * @param priceFeedAddress The address of the price feed.
     * @param maxAge The maximum age (in seconds) of the price feed data to be considered valid.
     */
    function setAssetPriceFeed(address asset, address priceFeedAddress, uint256 maxAge) public onlyRole(ORACLE_MANAGER_ROLE) {
        _setAssetPriceFeed(asset, priceFeedAddress, maxAge);
    }

    function _setAssetPriceFeed(address asset, address priceFeedAddress, uint256 maxAge) internal {
        if(priceFeedAddress == address(0) || asset == address(0)) {
            revert ZeroAddress();
        }

        if (maxAge == 0) {
            revert ZeroAge();
        }

        assetPriceFeeds[asset] = AssetPriceFeed(AggregatorV3Interface(priceFeedAddress), maxAge);
        emit AssetPriceFeedSet(asset, priceFeedAddress, maxAge);
    }

    /**
     * @notice Retrieves the latest price for a given asset.
     * @param asset The address of the asset.
     * @return The latest price of the asset.
     */
    function getLatestPrice(address asset) public view returns (uint256) {
        AssetPriceFeed storage priceFeed = assetPriceFeeds[asset];
        if(address(priceFeed.priceFeed) == address(0)) {
            revert PriceFeedNotSet();
        }

        (, int256 price,, uint256 timeStamp,) = priceFeed.priceFeed.latestRoundData();
        uint256 age = block.timestamp - timeStamp;
        if (age > priceFeed.maxAge) {
            revert PriceFeedTooStale(age, priceFeed.maxAge);
        }

        if (price <= 0) {
            revert InvalidPriceValue(price);
        }

        return uint256(price);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
