// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";

import {ynBase} from "src/ynBase.sol";


interface IynEigenEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
    event AssetRetrieved(IERC20 asset, uint256 amount, address destination);
    event LSDStakingNodeCreated(uint256 nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint256 maxNodeCount); 
    event DepositsPausedUpdated(bool paused);
}

contract ynEigen is IynEigen, ynBase, ReentrancyGuardUpgradeable, IynEigenEvents {
    using SafeERC20 for IERC20;

    struct Asset {
        uint256 balance;
        // Add extra fields here
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 asset);
    error Paused();
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch(uint256 assetsCount, uint256 stakedAssetsCount);
    error AssetRetrievalLengthMismatch(uint256 assetsCount, uint256 amountsCount);
    error NotStrategyManager(address msgSender);
    error InsufficientAssetBalance(IERC20 asset, uint256 balance, uint256 requestedAmount);
    error ZeroShares();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    mapping(address => Asset) public assets;

    address public yieldNestStrategyManager;
    IAssetRegistry public assetRegistry;

    bool public depositsPaused;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        string name;
        string symbol;
        IAssetRegistry assetRegistry;
        address yieldNestStrategyManager;
        address admin;
        address pauser;
        address unpauser;
        address[] pauseWhitelist;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.assetRegistry))
        notZeroAddress(address(init.admin))
        initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __ynBase_init(init.name, init.symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);

        assetRegistry = init.assetRegistry;
        yieldNestStrategyManager = init.yieldNestStrategyManager;

        _setTransfersPaused(true);  // transfers are initially paused
        _updatePauseWhitelist(init.pauseWhitelist, true);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits a specified amount of an asset into the contract and mints shares to the receiver.
     * @dev This function first checks if the asset is supported, then converts the asset amount to unitOfAccount equivalent,
     * calculates the shares to be minted based on the unitOfAccount value, mints the shares to the receiver, and finally
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

        asset.safeTransferFrom(sender, address(this), amount);

        // Convert the value of the asset deposited to unitOfAccount
        uint256 assetAmountInUnitOfAccount = assetRegistry.convertToUnitOfAccount(asset, amount);
        // Calculate how many shares to be minted using the same formula as ynUnitOfAccount
        shares = _convertToShares(assetAmountInUnitOfAccount, Math.Rounding.Floor);

        if (shares == 0) {
            revert ZeroShares();
        }

        // Mint the calculated shares to the receiver 
        _mint(receiver, shares);

        assets[address(asset)].balance += amount;        

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

        // Can only happen in bootstrap phase if `totalAssets` and `totalSupply` could be manipulated
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

    /**
     * @notice Converts a given amount of a specific asset to shares
     * @param asset The ERC-20 asset to be converted
     * @param amount The amount of the asset to be converted
     * @return shares The equivalent amount of shares for the given amount of the asset
     */
    function convertToShares(IERC20 asset, uint256 amount) public view returns(uint256 shares) {

        if(assetIsSupported(asset)) {
           uint256 assetAmountInUnitOfAccount = assetRegistry.convertToUnitOfAccount(asset, amount);
           shares = _convertToShares(assetAmountInUnitOfAccount, Math.Rounding.Floor);
        } else {
            revert UnsupportedAsset(asset);
        }
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
        return assetRegistry.totalAssets();
    }

    /**
     * @notice Retrieves the balances of specified assets.
     * @param assetsArray An array of ERC20 tokens for which to retrieve balances.
     * @return balances An array of balances corresponding to the input assets.
     */
    function assetBalances(IERC20[] calldata assetsArray) public view returns (uint256[] memory balances) {

        uint256 assetsArrayLength = assetsArray.length;
        balances = new uint256[](assetsArrayLength);
        for (uint256 i = 0; i < assetsArrayLength; i++) {
            balances[i] = assets[address(assetsArray[i])].balance;
        }
    }

    /**
     * @notice Retrieves the balance of a specific asset.
     * @param asset The ERC20 token for which to retrieve the balance.
     * @return balance The balance of the specified asset.
     */
    function assetBalance(IERC20 asset) public view returns (uint256 balance) {
        balance = assets[address(asset)].balance;
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
     */
    function retrieveAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) public onlyStrategyManager {

        uint256 assetsToRetrieveLength = assetsToRetrieve.length;
        if (assetsToRetrieveLength != amounts.length) {
            revert AssetRetrievalLengthMismatch(assetsToRetrieveLength, amounts.length);
        }

        address strategyManagerAddress = yieldNestStrategyManager;

        for (uint256 i = 0; i < assetsToRetrieveLength; i++) {
            IERC20 asset = assetsToRetrieve[i];
            if (!assetRegistry.assetIsSupported(asset)) {
                revert UnsupportedAsset(asset);
            }

            Asset memory assetState = assets[address(asset)];
            if (amounts[i] > assetState.balance) {
                revert InsufficientAssetBalance(asset, assetState.balance, amounts[i]);
            }

            assets[address(asset)].balance -= amounts[i];
            IERC20(asset).safeTransfer(strategyManagerAddress, amounts[i]);
            emit AssetRetrieved(asset, amounts[i], strategyManagerAddress);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  PAUSING  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Pauses deposits.
    /// @dev Can only be called by an account with the PAUSER_ROLE.
    function pauseDeposits() external onlyRole(PAUSER_ROLE) {
        depositsPaused = true;
        emit DepositsPausedUpdated(depositsPaused);
    }

    /// @notice Unpauses deposits.
    /// @dev Can only be called by an account with the UNPAUSER_ROLE.
    function unpauseDeposits() external onlyRole(UNPAUSER_ROLE) {
        depositsPaused = false;
        emit DepositsPausedUpdated(depositsPaused);
    }

    /**
     * @notice Checks if an asset is supported by the asset registry.
     * @param asset The ERC20 token to check for support.
     * @return bool True if the asset is supported, false otherwise.
     */
    function assetIsSupported(IERC20 asset) public view returns (bool) {
        return assetRegistry.assetIsSupported(asset);
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
        if(msg.sender != yieldNestStrategyManager) {
            revert NotStrategyManager(msg.sender);
        }
        _;
    }
}
