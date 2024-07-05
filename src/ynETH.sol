// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IynETH} from "src/interfaces/IynETH.sol";

import {ynBase} from "src/ynBase.sol";


interface IYnETHEvents {
    event DepositETHPausedUpdated(bool isPaused);
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares, uint256 totalDepositedInPool);
    event RewardsReceived(uint256 value, uint256 totalDepositedInPool);
    event ETHWithdrawn(uint256 ethAmount, uint256 totalDepositedInPool);
    event WithdrawnETHProcessed(uint256 ethAmount, uint256 totalDepositedInPool);
}

/**
 * @title ynETH
 * @dev The ynETH contract is a core component of the YieldNEst restaking protocol, facilitating the native restaking of ETH
 /// management of staking nodes, and distribution of rewards. It serves as the entry point for users to deposit ETH
 /// in exchange for ynETH tokens, representing their share of the staked ETH. 
 */
contract ynETH is IynETH, ynBase, IYnETHEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error Paused();
    error ZeroAddress();
    error ZeroETH();
    error NoDirectETHDeposit();
    error CallerNotStakingNodeManager(address expected, address provided);
    error NotRewardsDistributor();
    error InsufficientBalance();
    error TransferFailed();


    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES --------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    bool public depositsPaused;

    uint256 public totalDepositedInPool;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address pauser;
        address unpauser;
        IStakingNodesManager stakingNodesManager;
        IRewardsDistributor rewardsDistributor;
        address[] pauseWhitelist;
    }

    constructor() {
         _disableInitializers();
    }


    /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.pauser)
        notZeroAddress(init.unpauser)
        notZeroAddress(address(init.stakingNodesManager))
        notZeroAddress(address(init.rewardsDistributor))
        initializer {
        __AccessControl_init();
        __ynBase_init("ynETH", "ynETH");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);
        stakingNodesManager = init.stakingNodesManager;
        rewardsDistributor = init.rewardsDistributor;

        _setTransfersPaused(true);  // transfers are initially paused
        _updatePauseWhitelist(init.pauseWhitelist, true);
    }

    receive() external payable {
        revert NoDirectETHDeposit();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------
    
    /**
     * @notice Allows depositing ETH into the contract in exchange for shares.
     * @dev Mints shares equivalent to the deposited ETH value and assigns them to the receiver.
     * @param receiver The address to receive the minted shares.
     * @return shares The amount of shares minted for the deposited ETH.
     */
    function depositETH(address receiver) public payable returns (uint256 shares) {

        if (depositsPaused) {
            revert Paused();
        }

        if (msg.value == 0) {
            revert ZeroETH();
        }

        uint256 assets = msg.value;
        
        shares = previewDeposit(assets);

        _mint(receiver, shares);

        totalDepositedInPool += assets;
        emit Deposit(msg.sender, receiver, assets, shares, totalDepositedInPool);
    }

    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param assets The amount of assets to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Converts a given amount of assets to shares.
    /// @param assets The amount of assets to be converted.
    /// @return shares The equivalent amount of shares.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) {
            return ethAmount;
        }
        
        // deltaynETH = (ynETHSupply / totalControlled) * ethAmount
        return Math.mulDiv(
            ethAmount,
            totalSupply(),
            totalAssets(),
            rounding
        );
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS --------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Calculates the amount of assets that would be redeemed for a given amount of shares at current block
    /// @param shares The amount of shares to redeem.
    /// @return assets The equivalent amount of assets.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
       return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @notice Converts a given amount of shares to assets at current block
    /// @param shares The amount of shares to convert.
    /// @return assets The equivalent amount of assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
       return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @dev Internal implementation of {convertToAssets}.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {

        uint256 supply = totalSupply();

        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this call is made before boostrap call, not totalAssets
        if (supply == 0) {
            return shares;
        }
        return Math.mulDiv(shares, totalAssets(), supply, rounding);
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ASSETS -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Calculates the total assets controlled by the protocol.
    /// @dev This includes both the ETH deposited in the pool awaiting processing and the ETH already sent to validators on the beacon chain.
    /// @return total The total amount of ETH in wei.
    function totalAssets() public view returns (uint256) {
        uint256 total = 0;
        // Allocated ETH for deposits pending to be processed.
        total += totalDepositedInPool;
        // The total ETH sent to the beacon chain.
        total += totalDeposited();
        return total;
    }

    /// @notice Returns the total amount of ETH deposited across all validators.
    /// @return totalDeposited The total amount of ETH deposited in all validators.
    function totalDeposited() internal view returns (uint256) {

        return stakingNodesManager.totalDeposited();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING/UNSTAKING and REWARDS  -------------------
    //--------------------------------------------------------------------------------------

    /// @notice Receives rewards in ETH and adds them to the total deposited in the pool.
    /// @dev Only the rewards distributor contract can call this function.
    /// Reverts if called by any address other than the rewards distributor.
    function receiveRewards() external payable {
        if (msg.sender != address(rewardsDistributor)) {
            revert NotRewardsDistributor();
        }
        totalDepositedInPool += msg.value;

        emit RewardsReceived(msg.value, totalDepositedInPool);
    }

    /// @notice Withdraws a specified amount of ETH from the pool to the Staking Nodes Manager.
    /// @dev This function can only be called by the Staking Nodes Manager.
    /// @param ethAmount The amount of ETH to withdraw in wei.
    function withdrawETH(uint256 ethAmount) public onlyStakingNodesManager override {
        uint256 currentTotalDepositedInPool = totalDepositedInPool;

        // Check if the pool has enough ETH to fulfill the withdrawal request.
        if (currentTotalDepositedInPool < ethAmount) {
            revert InsufficientBalance();
        }

        // Deduct the withdrawal amount from the total deposited in the pool.
        uint256 newTotalDepositedInPool = currentTotalDepositedInPool - ethAmount;
        totalDepositedInPool = newTotalDepositedInPool;

        // Transfer the specified amount of ETH to the Staking Nodes Manager.
        (bool success, ) = payable(address(stakingNodesManager)).call{value: ethAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit ETHWithdrawn(ethAmount, newTotalDepositedInPool);
    }

    /// @notice Processes ETH that has been withdrawn from the staking nodes and adds it to the pool.
    /// @dev This function can only be called by the Staking Nodes Manager.
    /// It increases the total deposited in the pool by the amount of ETH sent with the call.
    function processWithdrawnETH() public payable onlyStakingNodesManager {
        totalDepositedInPool += msg.value;

        emit WithdrawnETHProcessed(msg.value, totalDepositedInPool);
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
        if (msg.sender != address(stakingNodesManager)) {
            revert CallerNotStakingNodeManager(
                address(stakingNodesManager),
                msg.sender
            );
        }
        _;
    }

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
