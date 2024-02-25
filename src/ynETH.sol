// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IDepositContract} from "./external/ethereum/IDepositContract.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IDepositPool} from "./interfaces/IDepositPool.sol";
import {IStakingNode,IStakingEvents} from "./interfaces/IStakingNode.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IynETH} from "./interfaces/IynETH.sol";
import {IWETH} from "./external/tokens/IWETH.sol";
 
contract ynETH is IynETH, ERC20Upgradeable, AccessControlUpgradeable, IStakingEvents {


    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error MinimumStakeBoundNotSatisfied();
    error StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error Paused();
    error ValueOutOfBounds(uint value);
    error TransfersPaused();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------


    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    uint public allocatedETHForDeposits;
    bool public isDepositETHPaused;

    /// @dev The value is in basis points (1/10000).
    uint public exchangeAdjustmentRate;

    uint public totalDepositedInPool;

    mapping (address => bool) pauseWhiteList;
    bool transfersPaused;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------


    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address pauser;
        IStakingNodesManager stakingNodesManager;
        IRewardsDistributor rewardsDistributor;
        IWETH wETH;
        uint exchangeAdjustmentRate;
        address[] pauseWhitelist;
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
        _grantRole(PAUSER_ROLE, init.pauser);
        stakingNodesManager = init.stakingNodesManager;
        rewardsDistributor = init.rewardsDistributor;
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
        transfersPaused = true; // transfers are initially paused

        _addToPauseWhitelist(init.pauseWhitelist);
    }

    receive() external payable {
        revert("ynETH: Cannot receive ETH directly");
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

    function setIsDepositETHPaused(bool isPaused) external onlyRole(PAUSER_ROLE) {
        isDepositETHPaused = isPaused;
        emit DepositETHPausedUpdated(isDepositETHPaused);
    }

    function setExchangeAdjustmentRate(uint256 newRate) external onlyStakingNodesManager {
        if (newRate > _BASIS_POINTS_DENOMINATOR) {
            revert ValueOutOfBounds(newRate);
        }
        exchangeAdjustmentRate = newRate;
        emit ExchangeAdjustmentRateUpdated(newRate);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BOOTSTRAP TRANSFERS PAUSE  ------------------------
    //--------------------------------------------------------------------------------------


    function _update(address from, address to, uint256 amount) internal virtual override {
        // revert if transfers are paused, the from is not on the whitelist and
        // it's neither a mint (from = 0) nor a burn (to = 0)
        if (transfersPaused && !pauseWhiteList[from] && from != address(0) && to != address(0)) {
            revert TransfersPaused();
        }
        super._update(from, to, amount);
    }

    /// @dev This is a one-way toggle. Once unpaused, transfers can't be paused again.
    function unpauseTransfers() external onlyRole(PAUSER_ROLE) {
        transfersPaused = false;
    }
    
    function addToPauseWhitelist(address[] memory whitelistedForTransfers) external onlyRole(PAUSER_ROLE) {
        _addToPauseWhitelist(whitelistedForTransfers);
    }

    function _addToPauseWhitelist(address[] memory whitelistedForTransfers) internal {
        for (uint i = 0; i < whitelistedForTransfers.length; i++) {
            pauseWhiteList[whitelistedForTransfers[i]] = true;
        }
    }
    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Caller is not the stakingNodesManager");
        _;
    }
}
