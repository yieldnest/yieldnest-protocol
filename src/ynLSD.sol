// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";

import {ynBase} from "src/ynBase.sol";

interface IynEigenEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
    event AssetRetrieved(IERC20 asset, uint256 amount, address destination);
    event LSDStakingNodeCreated(uint256 nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint256 maxNodeCount); 
    event DepositsPausedUpdated(bool paused);
}

contract ynLSD is IynEigen, ynBase, ReentrancyGuardUpgradeable, IynEigenEvents {
    using SafeERC20 for IERC20;

    struct AssetData {
        uint256 balance;
        bool active;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 asset);
    error Paused();
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch(uint256 assetsCount, uint256 stakedAssetsCount);
    error NotStrategyManager(address msgSender);

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------
    IRateProvider public rateProvider;

    /// @notice List of supported ERC20 asset contracts.
    IERC20[] public assets;

    mapping(address => AssetData) public assetData;
    
    bool public depositsPaused;

    IEigenStrategyManager eigenStrategyManager;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        string name;
        string symbol;
        IERC20[] assets;
        IRateProvider rateProvider;
        address admin;
        address pauser;
        address unpauser;
        address[] pauseWhitelist;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.rateProvider))
        notZeroAddress(address(init.admin))
        initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __ynBase_init(init.name, init.symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0)) {
                revert ZeroAddress();
            }
            assets.push(init.assets[i]);
            assetData[address(init.assets[i])] = AssetData({
                balance: 0,
                active: true
            });
        }

        rateProvider = init.rateProvider;

        _setTransfersPaused(true);  // transfers are initially paused
        _updatePauseWhitelist(init.pauseWhitelist, true);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits a specified amount of an asset into the contract and mints shares to the receiver.
     * @dev This function first checks if the asset is supported, then converts the asset amount to ETH equivalent,
     * calculates the shares to be minted based on the ETH value, mints the shares to the receiver, and finally
     * transfers the asset from the sender to the contract. Emits a Deposit event upon success.
     * @param asset The ERC20 asset to be deposited.
     * @param amount The amount of the asset to be deposited.
     * @param receiver The address to receive the minted shares.
     * @return shares The amount of shares minted to the receiver.
     */
    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) public nonReentrant returns (uint256 shares) {

        if (depositsPaused) {
            revert Paused();
        }

        return _deposit(asset, amount, receiver, msg.sender);
    }

    function _deposit(
        IERC20 asset,
        uint256 amount,
        address receiver,
        address sender
    ) internal returns (uint256 shares) {

        if (!assetIsSupported(asset)) {
            revert UnsupportedAsset(asset);
        }

        if (amount == 0) {
            revert ZeroAmount();
        }

        // Convert the value of the asset deposited to ETH
        uint256 assetAmountInETH = convertToUnitOfAccount(asset, amount);
        // Calculate how many shares to be minted using the same formula as ynETH
        shares = _convertToShares(assetAmountInETH, Math.Rounding.Floor);

        // Mint the calculated shares to the receiver 
        _mint(receiver, shares);

        // Transfer assets in after shares are computed since _convertToShares relies on totalAssets
        // which inspects asset.balanceOf(address(this))
        asset.safeTransferFrom(sender, address(this), amount);

        assetData[address(asset)].balance += amount;        

        emit Deposit(sender, receiver, amount, shares);
    }

    /**
     * @notice Converts an LRT amount to shares based on the current exchange rate and specified rounding method.
     * @param amount The amount of LRT to convert to shares.
     * @param rounding The rounding method to use for the calculation.
     * @return The number of shares equivalent to the given LRT amount.
     */
    function _convertToShares(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the bootstrap call, not totalAssets

        uint256 currentTotalSupply = totalSupply();
        uint256 currentTotalAssets = totalAssets();
        if (currentTotalSupply == 0) {
            return amount;
        }
        
        // Can only happen in bootstrap phase if `totalControlled` and `ynETHSupply` could be manipulated
        // independently. That should not be possible.
        return Math.mulDiv(
            amount,
            currentTotalSupply,
            currentTotalAssets,
            rounding
        );
    }


    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param asset The asset to be deposited.
    /// @param amount The amount of asset to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(IERC20 asset, uint256 amount) public view virtual returns (uint256) {
        return convertToShares(asset, amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  TOTAL ASSETS   -----------------------------------
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
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balanceInETH = convertToUnitOfAccount(assets[i], depositedBalances[i]);
            total += balanceInETH;
        }
        return total;
    }

   /**
     * @notice Converts a given amount of a specific asset to shares
     * @param asset The ERC-20 asset to be converted
     * @param amount The amount of the asset to be converted
     * @return shares The equivalent amount of shares for the given amount of the asset
     */
    function convertToShares(IERC20 asset, uint256 amount) public view returns(uint256 shares) {

        if(assetIsSupported(asset)) {
           uint256 assetAmountInUnitOfAccount = convertToUnitOfAccount(asset, amount);
           shares = _convertToShares(assetAmountInUnitOfAccount, Math.Rounding.Floor);
        } else {
            revert UnsupportedAsset(asset);
        }
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
        
        // Add balances for funds held directly in ynLSD.
        for (uint256 i = 0; i < assetsCount; i++) {
            IERC20 asset = assets[i];
            AssetData memory _assetData = assetData[address(asset)];
            assetBalances[i] += _assetData.balance;
        }

        uint256[] memory stakedAssetBalances = eigenStrategyManager.getStakedAssetsBalances(assets);

        if (stakedAssetBalances.length != assetsCount) {
            revert LengthMismatch(assetsCount, stakedAssetBalances.length);
        }

        for (uint256 i = 0; i < assetsCount; i++) {
            assetBalances[i] += stakedAssetBalances[i];
        }
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

    //--------------------------------------------------------------------------------------
    //----------------------------------  ASSET ALLOCATION  --------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Retrieves specified amounts of multiple assets and sends them to designated destinations.
     * @dev Transfers the specified amounts of assets to the corresponding destinations. This function can only be called by the strategy manager.
     * Reverts if the caller is not the strategy manager or if any of the assets are not supported.
     * @param assetsToRetrieve An array of ERC20 tokens to be retrieved.
     * @param amounts An array of amounts of the assets to be retrieved, corresponding to the `assetsToRetrieve` array.
     * @param destinations An array of addresses to which the assets are to be sent, corresponding to the `assetsToRetrieve` array.
     */
    function retrieveAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts,
        address[] calldata destinations
    ) public onlyStrategyManager {
        require(assetsToRetrieve.length == amounts.length && amounts.length == destinations.length, "LengthMismatch");

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            if (!assetData[address(asset)].active) {
                revert UnsupportedAsset(asset);
            }

            IERC20(asset).safeTransfer(destinations[i], amounts[i]);
            emit AssetRetrieved(assets[i], amounts[i], destinations[i]);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  PAUSING  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Pauses ETH deposits.
    /// @dev Can only be called by an account with the PAUSER_ROLE.
    function pauseDeposits() external onlyRole(PAUSER_ROLE) {
        depositsPaused = true;
        emit DepositsPausedUpdated(depositsPaused);
    }

    /// @notice Unpauses ETH deposits.
    /// @dev Can only be called by an account with the UNPAUSER_ROLE.
    function unpauseDeposits() external onlyRole(UNPAUSER_ROLE) {
        depositsPaused = false;
        emit DepositsPausedUpdated(depositsPaused);
    }

    function assetIsSupported(IERC20 asset) public returns (bool) {
        return assetData[address(asset)].active;
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

    modifier onlyStrategyManager() {
        if(msg.sender != address(eigenStrategyManager)) {
            revert NotStrategyManager(msg.sender);
        }
        _;
    }
}
