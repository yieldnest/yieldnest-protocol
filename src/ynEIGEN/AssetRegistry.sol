// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IRedemptionAssetsVaultExt} from "src/interfaces/IYieldNestStrategyManager.sol";

interface IAssetRegistryEvents {
    event AssetAdded(address indexed asset);
    event AssetDeleted(address indexed asset, uint256 assetIndex);
    event AssetActivated(address indexed asset);
    event AssetDisabled(address indexed asset);
    event PausedUpdated(bool paused);
}

/** @title AssetRegistry.sol
 *  @dev This contract handles the strategy management for ynEigen asset allocations.
 */
 contract AssetRegistry is IAssetRegistry, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IAssetRegistryEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error Paused();
    error AssetNotActive(address inactiveAsset);
    error AssetAlreadyActive(address asset);
    error AssetNotDisabled(address asset);
    error AssetBalanceNonZeroInPool(uint256 balanceInPool);
    error AssetBalanceNonZeroInStrategyManager(uint256 balanceInStrategyManager);
    error AssetNotFound(address absentAsset);
    error ZeroAddress();
    error LengthMismatch(uint256 length1, uint256 length2);
    error AssetAlreadyAvailable(address asset);
    error NoStrategyDefinedForAsset(IERC20 asset);
    error RateNotAvailableForAsset(IERC20 asset);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    
    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

     /// @notice List of supported ERC20 asset contracts.
    IERC20[] public assets;

    mapping(IERC20 => AssetData) public _assetData;

    bool public actionsPaused;

    IRateProvider public rateProvider;
    IYieldNestStrategyManager public strategyManager;
    IynEigen public ynEigen;


    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        IERC20[] assets;
        IRateProvider rateProvider;
        IYieldNestStrategyManager yieldNestStrategyManager;
        IynEigen ynEigen;
        address admin;
        address pauser;
        address unpauser;
        address assetManagerRole;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.rateProvider))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.pauser))
        notZeroAddress(address(init.unpauser))
        initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);
        _grantRole(ASSET_MANAGER_ROLE, init.assetManagerRole);

        strategyManager = init.yieldNestStrategyManager;
        rateProvider = init.rateProvider;
        ynEigen = init.ynEigen;

        uint256 assetsLength = init.assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            _addAsset(init.assets[i]);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ASSET MANAGEMENT  --------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Adds a new asset to the system.
     * @dev Adds an asset to the _assetData mapping and sets it as active. This function can only be called by the strategy manager.
     * @param asset The address of the ERC20 token to be added.
     */
    function addAsset(IERC20 asset)
    public
    onlyRole(ASSET_MANAGER_ROLE)
    notZeroAddress(address(asset))
    whenNotPaused {
        _addAsset(asset);
    }

    function _addAsset(IERC20 asset) private {
        if (_assetData[asset].status != AssetStatus.Unavailable) {
            revert AssetAlreadyAvailable(address(asset));
        }

        if (!strategyManager.supportsAsset(asset)) {
            revert NoStrategyDefinedForAsset(asset);
        }

        try rateProvider.rate(address(asset)) {
            // solhint-disable-previous-line no-empty-blocks
            // If the rate exists, do nothing
        } catch {
            revert RateNotAvailableForAsset(asset);
        }

        assets.push(asset);

        _assetData[asset] = AssetData({
            status: AssetStatus.Active
        });

        emit AssetAdded(address(asset));
    }

    /**
     * @notice Disables an existing asset in the system.
     * @dev Sets an asset as inactive in the _assetData mapping. This function can only be called by the strategy manager.
     * @param asset The address of the ERC20 token to be disabled.
     */
    function disableAsset(IERC20 asset)
    public
    onlyRole(ASSET_MANAGER_ROLE)
    notZeroAddress(address(asset))
    whenNotPaused {
        if (_assetData[asset].status != AssetStatus.Active) {
            revert AssetNotActive(address(asset));
        }

        _assetData[asset].status = AssetStatus.Disabled;

        emit AssetDisabled(address(asset));
    }

    /**
     * @notice Deletes an asset from the system entirely. Asset can only be deleted of no balance exists in the system.
     *         By that, no amount of that asset exists the ynEigen Pool or deposited in the EigenLayer strategy.
     * @dev Removes an asset from the _assetData mapping and the assets array. This function can only be called by the strategy manager.
     * @param asset The address of the ERC20 token to be deleted.
     */
    function deleteAsset(IERC20 asset)
    public
    onlyRole(ASSET_MANAGER_ROLE)
    notZeroAddress(address(asset))
    whenNotPaused {
        if (_assetData[asset].status != AssetStatus.Disabled) {
            // Asset can only be deleted it has been Disabled
            revert AssetNotDisabled(address(asset));
        }

        uint256 balanceInPool = ynEigen.assetBalance(asset);
        if (balanceInPool != 0) {
            revert AssetBalanceNonZeroInPool(balanceInPool);
        }

        uint256 strategyBalance = strategyManager.getStakedAssetBalance(asset);
        if (strategyBalance != 0) {
            revert AssetBalanceNonZeroInStrategyManager(strategyBalance);
        }

        // Remove asset from the assets array
        uint256 assetIndex = findAssetIndex(asset);

        // Move the last element into the place to delete
        assets[assetIndex] = assets[assets.length - 1];
        assets.pop();

        // Remove asset from the mapping
        delete _assetData[asset];

        emit AssetDeleted(address(asset), assetIndex);
    }

    /**
     * @notice Finds the index of an asset in the assets array.
     * @param asset The asset to find.
     * @return uint256 The index of the asset.
     */
    function findAssetIndex(IERC20 asset) internal view returns (uint256) {
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            if (assets[i] == asset) {
                return i;
            }
        }
        revert AssetNotFound(address(asset));
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ASSET VALUE  -------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the assets in the contract, gets the latest price for each asset from the oracle, 
     * multiplies it with the balance of the asset and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint256) {
        uint256 total = 0;

        uint256[] memory depositedBalances = getAllAssetBalances();

        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            uint256 balanceInUnitOfAccount = convertToUnitOfAccount(assets[i], depositedBalances[i]);
            total += balanceInUnitOfAccount;
        }
        return total;
    }

    /**
     * @notice Retrieves the total balances of all assets managed by the contract, both held directly and managed through strategies.
     * @dev This function aggregates the balances of each asset held directly by the contract and in each LSDStakingNode, 
     * including those managed by strategies associated with each asset.
     * @return assetBalances An array of the total balances for each asset, indexed in the same order as the `assets` array.
     */
    function getAllAssetBalances()
        public
        view
        returns (uint256[] memory assetBalances)
    {
        uint256 assetsCount = assets.length;

        assetBalances = new uint256[](assetsCount);

        // populate with the ynEigen balances
        assetBalances = ynEigen.assetBalances(assets);

        uint256[] memory stakedAssetBalances = strategyManager.getStakedAssetsBalances(assets);

        if (stakedAssetBalances.length != assetsCount) {
            revert LengthMismatch(assetsCount, stakedAssetBalances.length);
        }

        IRedemptionAssetsVaultExt redemptionAssetsVault = strategyManager.redemptionAssetsVault();
        uint256[] memory redemptionAssetBalances = new uint256[](assetsCount);
        if (address(redemptionAssetsVault) != address(0)) {
            redemptionAssetBalances = redemptionAssetsVault.assetBalances(assets);
        }

        for (uint256 i = 0; i < assetsCount; i++) {
            assetBalances[i] += stakedAssetBalances[i];
            assetBalances[i] += redemptionAssetBalances[i];
        }
    }

    /**
     * @notice Retrieves the list of all assets managed by the contract.
     * @dev Returns an array of addresses representing the ERC20 tokens considered as assets.
     * @return An array of ERC20 token addresses.
     */
    function getAssets() public view returns (IERC20[] memory) {
        return assets;
    }

    /**
     * @notice Converts the amount of a given asset to its equivalent value in the unit of account of the vault.
     * @dev This function takes into account the decimal places of the asset to ensure accurate conversion.
     * @param asset The ERC20 token to be converted to the unit of account.
     * @param amount The amount of the asset to be converted.
     * @return uint256 equivalent amount of the asset in the unit of account.
     */
    function convertToUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
        uint256 assetRate = rateProvider.rate(address(asset));
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
        return assetDecimals != 18
            ? assetRate * amount / (10 ** assetDecimals)
            : assetRate * amount / 1e18;
    }

    function convertFromUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
        uint256 assetRate = rateProvider.rate(address(asset));
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
        return assetDecimals != 18
            ? amount * (10 ** assetDecimals) / assetRate
            : amount * 1e18 / assetRate;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  PAUSING  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /** 
     * @notice Pauses management actions.
     * @dev Can only be called by an account with the PAUSER_ROLE.
     */
    function pauseActions() external onlyRole(PAUSER_ROLE) {
        actionsPaused = true;
        emit PausedUpdated(actionsPaused);
    }

    /** 
     * @notice Unpauses management actions.
     * @dev Can only be called by an account with the UNPAUSER_ROLE.
     */
    function unpauseActions() external onlyRole(UNPAUSER_ROLE) {
        actionsPaused = false;
        emit PausedUpdated(actionsPaused);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /** 
     * @notice Checks if an asset is supported.
     * @dev Returns true if the asset is active.
     */
    function assetIsSupported(IERC20 asset) public view returns (bool) {
        return _assetData[asset].status == AssetStatus.Active;
    }

    function assetData(IERC20 asset) public view returns (AssetData memory) {
         return _assetData[asset];
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

    modifier whenNotPaused() {
        if (actionsPaused) {
            revert Paused();
        }
        _;
    }
 }