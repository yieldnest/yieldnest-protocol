// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {ETH_ASSET, YNETH_UNIT} from "src/Constants.sol";

contract RedemptionAssetsVault is IRedemptionAssetsVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error TransferFailed(uint256 amount, address destination);
    error ZeroAddress();
    error InsufficientAssetBalance(address asset, uint256 requestedAmount, uint256 balance);
    error ContractPaused();
    error NotRedeemer(address caller);
    error AssetNotSupported();

    //--------------------------------------------------------------------------------------
    //----------------------------------  EVENTS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    event AssetDeposited(address indexed asset, address indexed sender, uint256 amount);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynEigen public ynEigen;
    IAssetRegistry public assetRegistry;
    bool public paused;
    address public redeemer;

    mapping(address asset => uint256 balance) public balances;

    // Initializer with Init struct and roles
    struct Init {
        address admin;
        address redeemer;
        IynEigen ynEigen;
        IAssetRegistry assetRegistry;
    }

    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.redeemer)
        notZeroAddress(address(init.ynEigen))
        notZeroAddress(address(init.assetRegistry))
        initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.admin);
        _grantRole(UNPAUSER_ROLE, init.admin);

        redeemer = init.redeemer;
        ynEigen = init.ynEigen;
        assetRegistry = init.assetRegistry;
        paused = false;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION  --------------------------------------
    //--------------------------------------------------------------------------------------

    function deposit(uint256 amount, address asset) external {
        if (!assetRegistry.assetIsSupported(IERC20(asset))) revert AssetNotSupported();

        balances[asset] += amount;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit AssetDeposited(asset, msg.sender, amount);
    }

    /** 
     * @notice Calculates the current redemption rate of ynETH to ETH.
     * @return The current redemption rate as a uint256.
     */
    function redemptionRate() public view returns (uint256) {
        return ynEigen.previewRedeem(YNETH_UNIT);
    }

    /** 
     * @notice Returns the total amount of assets available for redemption.
     * @return _availableRedemptionAssets The available unit-of-account-denominated balance as a uint256.
     */
    function availableRedemptionAssets() public view returns (uint256 _availableRedemptionAssets) {

        IERC20[] memory assets = assetRegistry.getAssets();

        uint256 len = assets.length;
        for (uint256 i = 0; i < len; ++i) {
            IERC20 asset = assets[i];
            uint256 balance = balances[address(asset)];
            if (balance > 0) _availableRedemptionAssets += assetRegistry.convertToUnitOfAccount(asset, balance);
        }
    }

    /** 
     * @notice Transfers a specified amount of redemption assets to a given address.
     * @param to The recipient address of the assets.
     * @param amount The amount of assets to transfer.
     * @dev Requires the caller to be the redeemer and the contract to not be paused.
     */
    function transferRedemptionAssets(address to, uint256 amount, bytes calldata /* data */) public onlyRedeemer whenNotPaused nonReentrant {
        uint256 balance = availableRedemptionAssets();
        if (balance < amount) {
            revert InsufficientAssetBalance(ETH_ASSET, amount, balance);
        }

        IERC20[] memory assets = assetRegistry.getAssets();
        for (uint256 i = 0; i < assets.length; ++i) {
            IERC20 asset = assets[i];
            uint256 assetBalance = balances[address(asset)];
            if (assetBalance > 0) {
                uint256 assetBalanceInUnit = assetRegistry.convertToUnitOfAccount(asset, assetBalance);
                if (assetBalanceInUnit >= amount) {
                    uint256 reqAmountInAsset = assetRegistry.convertFromUnitOfAccount(asset, amount);
                    IERC20(asset).safeTransfer(to, reqAmountInAsset);
                    balances[address(asset)] -= reqAmountInAsset;
                    break;
                } else {
                    IERC20(asset).safeTransfer(to, assetBalance);
                    balances[address(asset)] = 0;
                    amount -= assetBalanceInUnit;
                }
            }
        }

        emit AssetTransferred(ETH_ASSET, msg.sender, to, amount);
    }

    /** 
     * @notice Withdraws a specified amount of redemption assets and processes them through ynETH.
     * @param amount The amount of ETH to withdraw and process.
     * @dev Requires the caller to be the redeemer and the contract to not be paused.
     */
    function withdrawRedemptionAssets(uint256 amount) public onlyRedeemer whenNotPaused nonReentrant {
        IERC20[] memory assets = assetRegistry.getAssets();
        for (uint256 i = 0; i < assets.length; ++i) {
            IERC20 asset = assets[i];
            uint256 assetBalance = balances[address(asset)];
            if (assetBalance > 0) {
                uint256 assetBalanceInUnit = assetRegistry.convertToUnitOfAccount(asset, assetBalance);
                if (assetBalanceInUnit >= amount) {
                    uint256 reqAmountInAsset = assetRegistry.convertFromUnitOfAccount(asset, amount);
                    ynEigen.processWithdrawn(reqAmountInAsset, address(asset));
                    balances[address(asset)] -= reqAmountInAsset;
                    break;
                } else {
                    ynEigen.processWithdrawn(assetBalance, address(asset));
                    balances[address(asset)] = 0;
                    amount -= assetBalanceInUnit;
                }
            }
        }
        emit AssetWithdrawn(ETH_ASSET, msg.sender, address(ynEigen), amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /** 
     * @notice Ensure that the given address is not the zero address.
     * @param _address The address to check.
     */
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    /** 
     * @notice Checks if the contract is not paused.
     */
    modifier whenNotPaused() {
        if (paused) {
            revert ContractPaused();
        }
        _;
    }

    /**
     * @notice Ensures that the caller has the REDEEMER_ROLE.
     */
    modifier onlyRedeemer() {
        if (msg.sender != redeemer) {
            revert NotRedeemer(msg.sender);
        }
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  PAUSE FUNCTIONS  ---------------------------------
    //--------------------------------------------------------------------------------------

    /** 
     * @notice Pauses the contract, preventing certain actions.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
    }

    /** 
     * @notice Unpauses the contract, allowing certain actions.
     */
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        paused = false;
    }
}
