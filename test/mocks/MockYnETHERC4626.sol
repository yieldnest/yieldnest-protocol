// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

import {IynETH} from "src/interfaces/IynETH.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "forge-std/console.sol";


// This mock contract simulates ynETH upgraded to ERC4626, with an underlying Ethereum pegged token, 
// referred to as Nest ETH (nETH). This model draws inspiration from sfrxETH/frxETH.
contract MockYnETHERC4626 is IynETH, AccessControlUpgradeable, ERC4626Upgradeable {

    /// @notice Emitted when a user stakes ETH and receives ynETH.
    /// @param staker The address of the user staking ETH.
    /// @param ethAmount The amount of ETH staked.
    /// @param ynETHAmount The amount of ynETH received.
    event Staked(address indexed staker, uint256 ethAmount, uint256 ynETHAmount);
    event DepositETHPausedUpdated(bool isPaused);

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    error Paused();
    error ValueOutOfBounds(uint256 value);


    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    bool public depositsPaused;
    // Storage variables

    uint256 public totalDepositedInPool;

    struct ReInit {

        IERC20 underlyingAsset;
    }

    /// @notice Reinitializes the mock contract with new parameters.
    /// @param reinit The initialization parameters.
    function reinitialize(ReInit memory reinit) external reinitializer(2) {
         __ERC4626_init(reinit.underlyingAsset);

         
    }

    /// @notice Allows depositing ETH into the contract in exchange for shares.
    /// @dev This function is a stub in the mock contract.
    /// @param receiver The address to receive the minted shares.
    /// @return shares The amount of shares minted for the deposited ETH, always returns 0 in this mock.
    function depositETH(address receiver) external payable override returns (uint256 shares) {
        // This is a stub function in the mock contract, so it does not perform any actions.
        // In a real implementation, this function would handle deposit logic.
        receiver; // This is to silence unused variable warning.
        return 0;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {

        if (depositsPaused) {
            console.log("System is paused");
            revert Paused();
        }
    
        require(assets > 0, "assets == 0");


        shares = previewDeposit(assets);

        _mint(receiver, shares);

        totalDepositedInPool += assets;
        emit Deposit(msg.sender, receiver, assets, shares);
    }


    /// DUPLICATES from ynETH.sol

     /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view override returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) {
            return ethAmount;
        }
        return Math.mulDiv(
            ethAmount,
            totalSupply(),
            totalAssets(),
            rounding
        );
    }

    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param assets The amount of assets to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(uint256 assets) public view override(ERC4626Upgradeable, IynETH) returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        // allocated ETH for deposits pending to be processed
        total += totalDepositedInPool;
        /// The total ETH sent to the beacon chain 
        total += totalDepositedInValidators();
        return total;
    }

    function totalDepositedInValidators() internal view returns (uint256) {
        IStakingNode[]  memory nodes = stakingNodesManager.getAllNodes();
        uint256 totalDeposited = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalDeposited += nodes[i].getETHBalance();
        }
        return totalDeposited;
    }

        //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING/UNSTAKING and REWARDS  -------------------
    //--------------------------------------------------------------------------------------

    receive() external payable {
        revert("ynETH: Cannot receive ETH directly");
    }

    function receiveRewards() external payable {
        require(msg.sender == address(rewardsDistributor), "Caller is not the stakingNodesManager");
        totalDepositedInPool += msg.value;
    }

    function withdrawETH(uint256 ethAmount) public onlyStakingNodesManager override {
        require(totalDepositedInPool >= ethAmount, "Insufficient balance");

        payable(address(stakingNodesManager)).transfer(ethAmount);
        totalDepositedInPool -= ethAmount;
    }

    function processWithdrawnETH() public payable onlyStakingNodesManager {
        totalDepositedInPool += msg.value;
    }

    /// @notice Pauses ETH deposits.
    /// @dev Can only be called by an account with the PAUSER_ROLE.
    function pauseDeposits() external onlyRole(PAUSER_ROLE) {
        depositsPaused = true;
        emit DepositETHPausedUpdated(depositsPaused);
    }

    /// @notice Unpauses ETH deposits.
    /// @dev Can only be called by an account with the UNPAUSER_ROLE.
    function unpauseDeposits() external onlyRole(UNPAUSER_ROLE) {
        depositsPaused = false;
        emit DepositETHPausedUpdated(depositsPaused);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Caller is not the stakingNodesManager");
        _;
    }

}
