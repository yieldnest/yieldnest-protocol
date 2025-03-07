// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {ETH_ASSET, YNETH_UNIT} from "src/Constants.sol";


contract ynETHRedemptionAssetsVault is IRedemptionAssetsVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error TransferFailed(uint256 amount, address destination);
    error ZeroAddress();
    error InsufficientAssetBalance(address asset, uint256 requestedAmount, uint256 balance);
    error ContractPaused();
    error NotRedeemer(address caller);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynETH public ynETH;
    bool public paused;
    address public redeemer;

    // Initializer with Init struct and roles
    struct Init {
        address admin;
        address redeemer;
        IynETH ynETH;
    }

    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.redeemer)
        notZeroAddress(address(init.ynETH))
        initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.admin);
        _grantRole(UNPAUSER_ROLE, init.admin);

        redeemer = init.redeemer;
        ynETH = init.ynETH;
        paused = false;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION  --------------------------------------
    //--------------------------------------------------------------------------------------

    /** 
     * @notice Accepts incoming ETH deposits.
     */
    receive() external payable {
        emit AssetsDeposited(msg.sender, ETH_ASSET, msg.value);
    }

    /** 
     * @notice Calculates the current redemption rate of ynETH to ETH.
     * @return The current redemption rate as a uint256.
     */
    function redemptionRate() public view returns (uint256) {
        return ynETH.previewRedeem(YNETH_UNIT);
    }

    /** 
     * @notice Returns the total amount of ETH available for redemption.
     * @return The available ETH balance as a uint256.
     */
    function availableRedemptionAssets() public view returns (uint256) {
        return address(this).balance;
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

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed(amount, to);
        }
        emit AssetTransferred(ETH_ASSET, msg.sender, to, amount);
    }

    /** 
     * @notice Withdraws a specified amount of redemption assets and processes them through ynETH.
     * @param amount The amount of ETH to withdraw and process.
     * @dev Requires the caller to be the redeemer and the contract to not be paused.
     */
    function withdrawRedemptionAssets(uint256 amount) public onlyRedeemer whenNotPaused nonReentrant {
        ynETH.processWithdrawnETH{ value: amount }();
        emit AssetWithdrawn(ETH_ASSET, msg.sender, address(ynETH), amount);
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
