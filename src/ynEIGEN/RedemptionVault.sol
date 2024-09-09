// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRedemptionVault} from "src/interfaces/IRedemptionVault.sol";

contract RedemptionVault is IRedemptionVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

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

    IynEigen public ynEIGEN;
    bool public paused;
    address public redeemer;

    // Initializer with Init struct and roles
    struct Init {
        address admin;
        address redeemer;
        IynEigen ynEIGEN;
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
        ynEIGEN = init.ynEIGEN;
        paused = false;
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------  DEPOSIT  ---------------------------------------
    //--------------------------------------------------------------------------------------

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION  --------------------------------------
    //--------------------------------------------------------------------------------------

    function redemptionRate(IERC20 _asset) public view returns (uint256) {
        return ynEIGEN.previewRedeem(_asset);
    }

    function availableRedemptionAssets(IERC20 asset) public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function transferRedemptionAssets(
        IERC20 asset,
        address to,
        uint256 amount,
        bytes calldata /* data */
    ) public onlyRedeemer whenNotPaused nonReentrant {

        uint256 balance = availableRedemptionAssets(asset);
        if (balance < amount) revert InsufficientAssetBalance(asset, amount, balance);

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed(amount, to);
        }
        emit AssetTransferred(ETH_ASSET, msg.sender, to, amount);
    }

    function withdrawRedemptionAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) public onlyRedeemer whenNotPaused nonReentrant {
        ynEIGEN.retrieveAssets(assetsToRetrieve, amounts);
        // emit AssetWithdrawn(ETH_ASSET, msg.sender, address(ynETH), amount); // @todo
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
