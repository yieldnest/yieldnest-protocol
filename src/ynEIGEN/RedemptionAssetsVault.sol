// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRedemptionAssetsVault} from "./interfaces/IRedemptionAssetsVault.sol";
import {YNETH_UNIT} from "src/Constants.sol";

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
    address public tokenStakingNodesManager;

    mapping(address asset => uint256 balance) private _assets;

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
        notZeroAddress(address(init.ynEIGEN))
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

    function deposit(uint256 _amount, address _asset) external {
        // if (msg.sender != address(tokenStakingNodesManager)) revert InvalidCaller(); // @todo
        if (msg.sender != address(tokenStakingNodesManager)) revert("InvalidCaller");

        _assets[_asset] += _amount;

        // emit AssetDeposited(_amount, _asset); // @todo
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION  --------------------------------------
    //--------------------------------------------------------------------------------------

    function redemptionRate(IERC20 _asset) public view returns (uint256) {
        return ynEIGEN.previewRedeem(_asset, YNETH_UNIT); // ynEIGEN to Asset (sfrxETH/stETH...)
    }

    function availableRedemptionAssets(address _asset) public view returns (uint256) {
        return _assets[_asset];
    }

    function transferRedemptionAssets(
        address _asset,
        address _to,
        uint256 _amount,
        bytes calldata /* data */
    ) public onlyRedeemer whenNotPaused nonReentrant {

        _assets[_asset] -= _amount;
        IERC20(_asset).safeTransfer(_to, _amount);

        emit AssetTransferred(_asset, msg.sender, _to, _amount);
    }

    function withdrawRedemptionAssets(
        IERC20 _asset,
        uint256 _amount
    ) public onlyRedeemer whenNotPaused nonReentrant {

        IynEigen _ynEIGEN = ynEIGEN;
        _ynEIGEN.processWithdrawn(_amount, _asset);
        _asset.safeTransfer(address(_ynEIGEN), _amount);

        // emit AssetWithdrawn(_assetsToRetrieve, _amounts, msg.sender); // @todo
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
    //------------------------------------  SWEEP ------------------------------------------
    //--------------------------------------------------------------------------------------

    // function sweep // @todo

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
