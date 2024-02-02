// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDepositPool} from "./interfaces/IDepositPool.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";

import {IynETH} from "./interfaces/IynETH.sol";
import {IDepositContract} from "./interfaces/IDepositContract.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface StakingEvents {
    /// @notice Emitted when a user stakes ETH and receives ynETH.
    /// @param staker The address of the user staking ETH.
    /// @param ethAmount The amount of ETH staked.
    /// @param ynETHAmount The amount of ynETH received.
    event Staked(address indexed staker, uint256 ethAmount, uint256 ynETHAmount);
    event DepositETHPausedUpdated(bool isPaused);
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
}
 
contract ynETH is IynETH, ERC20Upgradeable, AccessControlUpgradeable, StakingEvents {

    // Errors.
    error MinimumStakeBoundNotSatisfied();
    error StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error Paused();

    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    uint public allocatedETHForDeposits;
    bool public isDepositETHPaused;
    // Storage variables

    /// As the adjustment is applied to the exchange rate, the result is reflected in any user interface which shows the
    /// amount of ynETH received when staking, meaning there is no surprise for users when staking or unstaking.
    /// @dev The value is in basis points (1/10000).
    uint16 public exchangeAdjustmentRate;

    uint public totalDepositedInPool;

    /// @dev A basis point (often denoted as bp, 1bp = 0.01%) is a unit of measure used in finance to describe
    /// the percentage change in a financial instrument. This is a constant value set as 10000 which represents
    /// 100% in basis point terms.
    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        IStakingNodesManager stakingNodesManager;
        IRewardsDistributor rewardsDistributor;
        IWETH wETH;
    }

    constructor(
    ) {
        // TODO; re-enable this
         //_disableInitializers();
    }


    /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControl_init();
        __ERC20_init("ynETH", "ynETH");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        stakingNodesManager = init.stakingNodesManager;
        rewardsDistributor = init.rewardsDistributor;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    function depositETH(address receiver) public payable returns (uint shares) {

        if (isDepositETHPaused) {
            revert Paused();
        }

        require(msg.value > 0, "msg.value == 0");

        uint assets = msg.value;

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
            totalSupply() * uint256(_BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalAssets() * uint256(_BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }

    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param assets The amount of assets to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function totalAssets() public view returns (uint) {
        uint total = 0;
        // allocated ETH for deposits pending to be processed
        total += totalDepositedInPool;
        /// The total ETH sent to the beacon chain 
        total += totalDepositedInValidators();
        return total;
    }

    function totalDepositedInValidators() internal view returns (uint) {
        IStakingNode[]  memory nodes = stakingNodesManager.getAllNodes();
        uint totalDeposited = 0;
        for (uint i = 0; i < nodes.length; i++) {
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

    function withdrawETH(uint ethAmount) public onlyStakingNodesManager override {
        require(totalDepositedInPool >= ethAmount, "Insufficient balance");

        payable(address(stakingNodesManager)).transfer(ethAmount);
        totalDepositedInPool -= ethAmount;
    }

    function processWithdrawnETH() public payable onlyStakingNodesManager {
        totalDepositedInPool += msg.value;
    }

    function toggleDepositETHPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isDepositETHPaused = !isDepositETHPaused;
        emit DepositETHPausedUpdated(isDepositETHPaused);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Caller is not the stakingNodesManager");
        _;
    }
}
