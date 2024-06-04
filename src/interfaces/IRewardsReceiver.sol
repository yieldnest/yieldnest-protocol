// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

// --------------------------------------------------------------------------------------
// $$\     $$\ $$\           $$\       $$\ $$\   $$\                       $$\     
// \$$\   $$  |\__|          $$ |      $$ |$$$\  $$ |                      $$ |    
//  \$$\ $$  / $$\  $$$$$$\  $$ | $$$$$$$ |$$$$\ $$ | $$$$$$\   $$$$$$$\ $$$$$$\   
//   \$$$$  /  $$ |$$  __$$\ $$ |$$  __$$ |$$ $$\$$ |$$  __$$\ $$  _____|\_$$  _|  
//    \$$  /   $$ |$$$$$$$$ |$$ |$$ /  $$ |$$ \$$$$ |$$$$$$$$ |\$$$$$$\    $$ |    
//     $$ |    $$ |$$   ____|$$ |$$ |  $$ |$$ |\$$$ |$$   ____| \____$$\   $$ |$$\ 
//     $$ |    $$ |\$$$$$$$\ $$ |\$$$$$$$ |$$ | \$$ |\$$$$$$$\ $$$$$$$  |  \$$$$  |
//     \__|    \__| \_______|\__| \_______|\__|  \__| \_______|\_______/    \____/ 
//--------------------------------------------------------------------------------------
//----------------------------------  IRewardsReceiver  --------------------------------
//--------------------------------------------------------------------------------------

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface IRewardsReceiver {
    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address withdrawer;
    }

    /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external;

    /// @notice Transfers the given amount of ETH to an address.
    /// @dev Only callable by the withdrawer.
    function transferETH(address payable to, uint256 amount) external;

    /// @notice Transfers the given amount of an ERC20 token to an address.
    /// @dev Only callable by the withdrawer.
    function transferERC20(IERC20 token, address to, uint256 amount) external;
}
