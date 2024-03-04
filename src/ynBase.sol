// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract ynBase is ERC20Upgradeable, AccessControlUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error TransfersPaused();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  STORAGE  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /// @custom:storage-location erc7201:yieldnest.storage.ynBase
    struct ynBaseStorage {
        mapping (address => bool) pauseWhiteList;
        bool transfersPaused;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201:yieldnest.storage.ynBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ynBaseStorageLocation = 0x7e7ba5b20f89141f0255e9704ce6ce6e55f5f28e4fc0d626fc76bedba3053200;

    function _getYnBaseStorage() private pure returns (ynBaseStorage storage $) {
        assembly {
            $.slot := ynBaseStorageLocation
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ynBase_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init(name_, symbol_);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BOOTSTRAP TRANSFERS PAUSE  -----------------------
    //--------------------------------------------------------------------------------------

    function _update(address from, address to, uint256 amount) internal virtual override {

        ynBaseStorage storage $ = _getYnBaseStorage();
        // revert if transfers are paused, the from is not on the whitelist and
        // it's neither a mint (from = 0) nor a burn (to = 0)
        if ($.transfersPaused && !$.pauseWhiteList[from] && from != address(0) && to != address(0)) {
            revert TransfersPaused();
        }
        super._update(from, to, amount);
    }

    /// @dev This is a one-way toggle. Once unpaused, transfers can't be paused again.
    function unpauseTransfers() external onlyRole(PAUSER_ROLE) {
        ynBaseStorage storage $ = _getYnBaseStorage();
        $.transfersPaused = false;
    }
    
    function addToPauseWhitelist(address[] memory whitelistedForTransfers) external onlyRole(PAUSER_ROLE) {
        _addToPauseWhitelist(whitelistedForTransfers);
    }

    function _addToPauseWhitelist(address[] memory whitelistedForTransfers) internal {

        ynBaseStorage storage $ = _getYnBaseStorage();
        for (uint256 i = 0; i < whitelistedForTransfers.length; i++) {
            $.pauseWhiteList[whitelistedForTransfers[i]] = true;
        }
    }

    function _setTransfersPaused(bool _transfersPaused) internal {
        ynBaseStorage storage $ = _getYnBaseStorage();
        $.transfersPaused = _transfersPaused;
    }

    /**
     * @dev Returns true if the address is whitelisted for transfers during pause, false otherwise.
     */
    function isAddressWhitelisted(address addr) public view returns (bool) {
        ynBaseStorage storage $ = _getYnBaseStorage();
        return $.pauseWhiteList[addr];
    }

    /**
     * @dev Returns true if the address is in the pause whitelist, false otherwise.
     */
    function pauseWhiteList(address addr) public view returns (bool) {
        ynBaseStorage storage $ = _getYnBaseStorage();
        return $.pauseWhiteList[addr];
    }
}

