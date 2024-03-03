// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IStakingNode,IStakingEvents} from "./interfaces/IStakingNode.sol";
import {IynETH} from "./interfaces/IynETH.sol";
import {ynBase} from "./ynBase.sol";
 
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
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant BASIS_POINTS_DENOMINATOR = 10_000;

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
        _addToPauseWhitelist(init.pauseWhitelist);
    }

    receive() external payable {
        revert NoDirectETHDeposit();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

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

    // TODO: solve for deposit and mint to adjust to new variables

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

    function totalAssets() public view returns (uint256) {
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

    function receiveRewards() external payable {
        if (msg.sender != address(rewardsDistributor)) {
            revert NotRewardsDistributor();
        }
        totalDepositedInPool += msg.value;
    }

    function withdrawETH(uint256 ethAmount) public onlyStakingNodesManager override {
        if (totalDepositedInPool < ethAmount) {
            revert InsufficientBalance();
        }

        totalDepositedInPool -= ethAmount;
        payable(address(stakingNodesManager)).transfer(ethAmount);
    }

    function processWithdrawnETH() public payable onlyStakingNodesManager {
        totalDepositedInPool += msg.value;
    }

    function updateDepositsPaused(bool isPaused) external onlyRole(PAUSER_ROLE) {
        depositsPaused = isPaused;
        emit DepositETHPausedUpdated(depositsPaused);
    }

    function setExchangeAdjustmentRate(uint256 newRate) external onlyStakingNodesManager {
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
