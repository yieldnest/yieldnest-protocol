// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {AggregatorV3Interface} from "./external/chainlink/AggregatorV3Interface.sol";

contract YieldNestOracle is AccessControlUpgradeable {
    struct AssetPriceFeed {
        AggregatorV3Interface priceFeed;
        uint256 maxAge; // in seconds
    }

    error PriceFeedTooStale(uint256 age, uint256 maxAge);
    error ZeroAddress();
    error ZeroAge();
    error ArraysLengthMismatch(uint256 assetsLength, uint256 priceFeedAddressesLength, uint256 maxAgesLength);

    mapping(address => AssetPriceFeed) public assetPriceFeeds;

    struct Init {
        address[] assets;
        address[] priceFeedAddresses;
        uint256[] maxAges;
        address admin;
        address oracleManager;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.oracleManager)
        initializer {
         __AccessControl_init();
        _grantRole(ADMIN_ROLE, init.admin);
        _grantRole(ORACLE_MANAGER_ROLE, init.oracleManager);

        if (init.assets.length != init.priceFeedAddresses.length || init.assets.length != init.maxAges.length) {
            revert ArraysLengthMismatch({assetsLength: init.assets.length, priceFeedAddressesLength: init.priceFeedAddresses.length, maxAgesLength: init.maxAges.length});
        }
        for (uint256 i = 0; i < init.assets.length; i++) {
            if(init.assets[i] == address(0)) {
                revert ZeroAddress();
            }
            if(init.priceFeedAddresses[i] == address(0)) {
                revert ZeroAddress();
            }
            setAssetPriceFeed(init.assets[i], init.priceFeedAddresses[i], init.maxAges[i]);
        }
    }


    function setAssetPriceFeed(address asset, address priceFeedAddress, uint256 maxAge) public onlyRole(ORACLE_MANAGER_ROLE) {
        if(priceFeedAddress == address(0) || asset == address(0)) revert ZeroAddress();
        if(maxAge <= 0) revert ZeroAge();
        _setAssetPriceFeed(asset, priceFeedAddress, maxAge);
    }

    function _setAssetPriceFeed(address asset, address priceFeedAddress, uint256 maxAge) internal {
        assetPriceFeeds[asset] = AssetPriceFeed(AggregatorV3Interface(priceFeedAddress), maxAge);
    }

    function getLatestPrice(address asset) public view returns (uint256) {
        AssetPriceFeed storage priceFeed = assetPriceFeeds[asset];
        require(address(priceFeed.priceFeed) != address(0), "Price feed not set");

        (, int256 price,, uint256 timeStamp,) = priceFeed.priceFeed.latestRoundData();
        uint256 age = block.timestamp - timeStamp;
        if (age > priceFeed.maxAge) {
            revert PriceFeedTooStale(age, priceFeed.maxAge);
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
