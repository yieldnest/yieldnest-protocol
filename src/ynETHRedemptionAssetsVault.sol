// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";


contract ynETHRedemptionAssetsVault is IRedemptionAssetsVault, Initializable, AccessControlUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error TransferFailed(uint256 amount, address destination);
    error ZeroAddress();
    error InsufficientAssetBalance(address asset, uint256 requestedAmount, uint256 balance);
    error ContractPaused();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    address public constant ETH_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant YN_ETH_UNIT = 1e18;

    IynETH public ynETH;
    bool private _paused;

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
        _grantRole(REDEEMER_ROLE, init.redeemer);
        _grantRole(PAUSER_ROLE, init.admin);
        _grantRole(UNPAUSER_ROLE, init.admin);

        ynETH = init.ynETH;
        _paused = false;
    }

    receive() external payable {
        emit AssetsDeposited(msg.sender, ETH_ASSET, msg.value);
    }

    function redemptionRate() public view returns (uint256) {
        return ynETH.previewRedeem(YN_ETH_UNIT);
    }

    function availableRedemptionAssets(address /* redeemer */) public view returns (uint256) {
        return address(this).balance;
    }

    function transferRedemptionAssets(address to, uint256 amount) public onlyRole(REDEEMER_ROLE) whenNotPaused {
        uint256 balance = availableRedemptionAssets(msg.sender);
        if (balance < amount) {
            revert InsufficientAssetBalance(ETH_ASSET, amount, balance);
        }

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed(amount, to);
        }
        emit AssetTransferred(ETH_ASSET, msg.sender, to, amount);
    }

    function withdrawRedemptionAssets(uint256 amount) public onlyRole(REDEEMER_ROLE) whenNotPaused {
        ynETH.processWithdrawnETH{ value: amount }();
        emit AssetWithdrawn(ETH_ASSET, msg.sender, address(ynETH), amount);
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

    /// @notice Checks if the contract is not paused.
    modifier whenNotPaused() {
        if (_paused) {
            revert ContractPaused();
        }
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  PAUSE FUNCTIONS  ---------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Pauses the contract, preventing certain actions.
    function pause() external onlyRole(PAUSER_ROLE) {
        _paused = true;
    }

    /// @notice Unpauses the contract, allowing certain actions.
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _paused = false;
    }
}

