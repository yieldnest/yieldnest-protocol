// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IStakingNode,IStakingEvents} from "./interfaces/IStakingNode.sol";
import {IynETH} from "./interfaces/IynETH.sol";
import {ynBase} from "./ynBase.sol";

/**
 * @title ynETH
 * @dev The ynETH contract is a core component of the YieldNEst restaking protocol, facilitating the native restaking of ETH
 /// management of staking nodes, and distribution of rewards. It serves as the entry point for users to deposit ETH
 /// in exchange for ynETH tokens, representing their share of the staked ETH. 
 */
contract ynETH is IynETH, ynBase, IStakingEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error MinimumStakeBoundNotSatisfied();
    error StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error Paused();
    error ValueOutOfBounds(uint256 value);
    error ZeroAddress();
    error ExchangeAdjustmentRateOutOfBounds(uint256 exchangeAdjustmentRate);
    error ZeroETH();
    error NoDirectETHDeposit();
    error CallerNotStakingNodeManager(address expected, address provided);
    error NotRewardsDistributor();
    error InsufficientBalance();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    uint256 public allocatedETHForDeposits;
    bool public depositsPaused;

    /// @dev The value is in basis points (1/10000).
    uint256 public exchangeAdjustmentRate;

    uint256 public totalDepositedInPool;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address pauser;
        IStakingNodesManager stakingNodesManager;
        IRewardsDistributor rewardsDistributor;
        uint256 exchangeAdjustmentRate;
        address[] pauseWhitelist;
    }

    constructor(
    ) {
         _disableInitializers();
    }


    /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.pauser)
        notZeroAddress(address(init.stakingNodesManager))
        notZeroAddress(address(init.rewardsDistributor))
        initializer {
        __AccessControl_init();
        __ynBase_init("ynETH", "ynETH");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        stakingNodesManager = init.stakingNodesManager;
        rewardsDistributor = init.rewardsDistributor;

        if (init.exchangeAdjustmentRate > BASIS_POINTS_DENOMINATOR) {
            revert ExchangeAdjustmentRateOutOfBounds(init.exchangeAdjustmentRate);
        }
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;

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

        totalDepositedInPool += msg.value;
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) {
            return ethAmount;
        }

        // deltaynETH = (1 - exchangeAdjustmentRate) * (ynETHSupply / totalControlled) * ethAmount
        //  If `(1 - exchangeAdjustmentRate) * ethAmount * ynETHSupply < totalControlled` this will be 0.
        
        // Can only happen in bootstrap phase if `totalControlled` and `ynETHSupply` could be manipulated
        // independently. That should not be possible.
        return Math.mulDiv(
            ethAmount,
            totalSupply() * uint256(BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalAssets() * uint256(BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }

    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param assets The amount of assets to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Calculates the total assets controlled by the protocol.
    /// @dev This includes both the ETH deposited in the pool awaiting processing and the ETH already sent to validators on the beacon chain.
    /// @return total The total amount of ETH in wei.
    function totalAssets() public view returns (uint256) {
        uint256 total = 0;
        // Allocated ETH for deposits pending to be processed.
        total += totalDepositedInPool;
        // The total ETH sent to the beacon chain.
        total += totalDepositedInValidators();
        return total;
    }

    /// @notice Calculates the total amount of ETH deposited across all validators.
    /// @dev Iterates through all staking nodes to sum up their ETH balances.
    /// @return totalDeposited The total amount of ETH deposited in all validators.
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

    /// @notice Receives rewards in ETH and adds them to the total deposited in the pool.
    /// @dev Only the rewards distributor contract can call this function.
    /// Reverts if called by any address other than the rewards distributor.
    function receiveRewards() external payable {
        if (msg.sender != address(rewardsDistributor)) {
            revert NotRewardsDistributor();
        }
        totalDepositedInPool += msg.value;
    }

    /// @notice Withdraws a specified amount of ETH from the pool to the Staking Nodes Manager.
    /// @dev This function can only be called by the Staking Nodes Manager.
    /// @param ethAmount The amount of ETH to withdraw in wei.
    function withdrawETH(uint256 ethAmount) public onlyStakingNodesManager override {
        // Check if the pool has enough ETH to fulfill the withdrawal request.
        if (totalDepositedInPool < ethAmount) {
            revert InsufficientBalance();
        }

        // Deduct the withdrawal amount from the total deposited in the pool.
        totalDepositedInPool -= ethAmount;
        // Transfer the specified amount of ETH to the Staking Nodes Manager.
        payable(address(stakingNodesManager)).transfer(ethAmount);
    }

    /// @notice Processes ETH that has been withdrawn from the staking nodes and adds it to the pool.
    /// @dev This function can only be called by the Staking Nodes Manager.
    /// It increases the total deposited in the pool by the amount of ETH sent with the call.
    function processWithdrawnETH() public payable onlyStakingNodesManager {
        totalDepositedInPool += msg.value;
    }

    /// @notice Updates the pause state of ETH deposits.
    /// @dev Can only be called by an account with the PAUSER_ROLE.
    /// @param isPaused The new pause state to set for ETH deposits.
    function updateDepositsPaused(bool isPaused) external onlyRole(PAUSER_ROLE) {
        depositsPaused = isPaused;
        emit DepositETHPausedUpdated(depositsPaused);
    }
    
    /// @notice Sets the exchange adjustment rate.
    /// @dev Can only be called by the admin..
    /// Reverts if the new rate exceeds the basis points denominator.
    /// @param newRate The new exchange adjustment rate to be set.
    function setExchangeAdjustmentRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRate > BASIS_POINTS_DENOMINATOR) {
            revert ValueOutOfBounds(newRate);
        }
        exchangeAdjustmentRate = newRate;
        emit ExchangeAdjustmentRateUpdated(newRate);
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
