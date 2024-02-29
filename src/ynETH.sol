// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Third-party imports: OZ
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {IynETH} from "./interfaces/IynETH.sol";
import {IDepositPool} from "./interfaces/IDepositPool.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";

// Third-party imports: ETH2
import {IDepositContract} from "./interfaces/IDepositContract.sol";

// Third-party imports: Other
import {IOracle} from "./interfaces/IOracle.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title ynETH
/// @notice TODO
contract ynETH is 
    ERC20Upgradeable, 
    AccessControlUpgradeable
{
    /******************************\
    |                              |
    |             Errors           |
    |                              |
    \******************************/

    error YnEth_MinimumStakeBoundNotSatisfied();
    error YnEth_StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error YnEth_Paused();
    error YnEth_ValueOutOfBounds(uint256 value);
    error YnEth_CallerNotStakingNodeManager(address expected, address actual);
    error YnEth_CallerNotRewardsDistributorOrStakingNodesManager(address expected1, address expected2, address actual);
    error YnEth_ZeroEth();
    error YnEth_DirectETHDepositsNotAllowed();
    error YnEth_InsufficientBalance(uint256 requested, uint256 available);
    error YnEth_DepositsPausedAlreadyCurrent();
    error YnEth_ExchangeAdjustmentRateOutOfBounds(uint256 value);

    /******************************\
    |                              |
    |             Events           |
    |                              |
    \******************************/

    event YnEth_Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event YnEth_EthReceived(address indexed from, uint256 indexed ethAmount);
    event YnEth_EthWithdrawn(uint256 indexed ethAmount);
    event YnEth_ExchangeAdjustmentRateUpdated(uint256 oldRate, uint256 newRate);
    event YnEth_DepositsPausedUpdated(bool paused);

    /******************************\
    |                              |
    |            Structs           |
    |                              |
    \******************************/

    /// @notice Configuration for contract initialization.
    /// @dev Only used in memory (i.e. layout doesn't matter!)
    /// @param admin The address of the account that gets the DEFAULT_ADMIN_ROLE.
    /// @param pauser The address of the account that gets the PAUSER_ROLE.
    /// @param stakingNodesManager The StakingNodesManager contract.
    /// @param rewardsDistributor The RewardsDistributor contract.
    /// @param wETH The WETH contract.
    /// @param exchangeAdjustmentRate The initial exchange adjustmnet rate.
    struct Init {
        address admin;
        address pauser;
        address stakingNodesManager;
        address rewardsDistributor;
        address wETH;
        uint256 exchangeAdjustmentRate;
    }

    /******************************\
    |                              |
    |           Constants          |
    |                              |
    \******************************/
    
    /// @notice The name of this ERC20 token.
    string private constant TOKEN_NAME = "ynETH";

    /// @notice The symbol of this ERC20 token.
    string private constant TOKEN_SYMBOL = "ynETH";

    /// @notice Role is allowed to set the pause state.
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The basis points denominator (100% = 100_00, 1% = 1_00).
    uint256 private constant BASIS_POINTS_DENOMINATOR = 100_00; 

    /******************************\
    |                              |
    |       Storage variables      |
    |                              |
    \******************************/

    /// @notice The StakingNodesManager contract.
    IStakingNodesManager public stakingNodesManager;

    /// @notice The RewardsDistributor contract.
    address public rewardsDistributor;

    //@audit This variable is never used
    // uint256 public allocatedETHForDeposits;

    /// @notice Indicates if deposits are currently paused.
    bool public depositsPaused;
    
    /// @notice The exchange adjustment rate in basis points (i.e. 100% = 10000, 1% = 100, 0.001% = 1).
    uint256 public exchangeAdjustmentRate;

    /// @notice The total amount of ETH (=assets) deposited into this contract.
    uint256 public totalDeposited;

    /******************************\
    |                              |
    |          Constructor         |
    |                              |
    \******************************/

    /// @notice The constructor.
    /// @dev calling _disableInitializers() to prevent the implementation from being initializable.
    constructor() {
       _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @param init The init params.
    function initialize(Init memory init) 
        external 
        notZeroAddress(init.admin)
        notZeroAddress(init.pauser)
        notZeroAddress(init.stakingNodesManager)
        notZeroAddress(init.rewardsDistributor)
        initializer 
    {
        // Initialize all the parent contracts.
        __AccessControl_init();
        __ERC20_init(TOKEN_NAME, TOKEN_SYMBOL);

        // Assign all the roles.
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);

        // Store configuration values.
        if (init.exchangeAdjustmentRate > BASIS_POINTS_DENOMINATOR) {
            revert YnEth_ExchangeAdjustmentRateOutOfBounds(init.exchangeAdjustmentRate);
        }
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
        
        // Store all of the addresses of interacting contracts.
        stakingNodesManager = IStakingNodesManager(init.stakingNodesManager);
        // NOTE: storing just an address since we never call a function in this contract.
        rewardsDistributor = init.rewardsDistributor;
    }

    /******************************\
    |                              |
    |         Core functions       |
    |                              |
    \******************************/

    //@check what about that first depositor bug, does that apply here?
    /// @notice Deposit ETH and receive ynETH.
    /// @param _receiver The account that receives the ynETH.
    /// @return shares The amount of ynETH send to the receiver.
    function deposit(address _receiver) 
        payable
        external 
        whenDepositsNotPaused
        returns (uint256 shares) 
    {
        if (msg.value == 0) {
            revert YnEth_ZeroEth();
        }
        uint256 assets = msg.value;
        shares = previewDeposit(assets);
        _mint(_receiver, shares);
        totalDeposited += shares;
        emit YnEth_Deposit(msg.sender, _receiver, assets, shares);
    }

    /// @notice Transfer ETH from this contract to the StakingNodesManager contract.
    /// @dev Only callable by the StakingNodesManager contract.
    /// @dev This function is called from the StakingNodesManager.registerValidator function.
    ///      Each validator will first acquire ynETH, and after that can/will be registered
    ///      as validator through the StakingNodesManager contract. In other words, the 
    ///      ETH to be used as "validator deposit" for each validator acutally got deposited
    ///      into ynETH. Therefore, when a validator is registered their 32 ETH will be 
    ///      transferred from this contract to the StakingNodesManager contract, after which
    ///      that contract will deposit the 32 ETH into the actual ETH2 deposit contract.
    /// @param _ethAmount The amount to withdraw.
    function withdrawETH(uint256 _ethAmount) 
        external 
        override 
        onlyStakingNodesManager  
    {
        if (totalDeposited < _ethAmount) {
            revert YnEth_InsufficientBalance(_ethAmount, totalDeposited);
        }
        totalDeposited -= _ethAmount;
        payable(address(stakingNodesManager)).call{value:_ethAmount}("");
        emit YnEth_EthWithdrawn(_ethAmount);
    }

    /******************************\
    |                              |
    |    Configuration functions   |
    |                              |
    \******************************/

    /// @notice Update deposits-are-paused.
    /// @dev Only callable by an account with the PAUSER_ROLE.
    /// @param _depositsPaused The new deposits-are-paused state.
    function updateDepositsPaused(bool _depositsPaused) 
        external 
        onlyRole(PAUSER_ROLE) 
    {
        if (_depositsPaused == depositsPaused) {
            revert YnEth_DepositsPausedAlreadyCurrent();
        }
        depositsPaused = _depositsPaused;
        emit YnEth_DepositsPausedUpdated(_depositsPaused);
    }
    
    /// @notice Update the exchange adjustment rate.
    /// @dev Only callable by the StakingNodesManager contract.
    /// @param _exchangeAdjustmentRate The new exchange adjustment rate.
    function updateExchangeAdjustmentRate(uint256 _exchangeAdjustmentRate) 
        external 
        onlyStakingNodesManager 
    {
        if (_exchangeAdjustmentRate > BASIS_POINTS_DENOMINATOR) {
            revert YnEth_ExchangeAdjustmentRateOutOfBounds(_exchangeAdjustmentRate);
        }
        emit YnEth_ExchangeAdjustmentRateUpdated(exchangeAdjustmentRate, _exchangeAdjustmentRate);
        exchangeAdjustmentRate = _exchangeAdjustmentRate;
    }

    /*************************************\
    |                                     |
    | View functions only used internally |
    |                                     |
    \*************************************/

    // TODO: solve for deposit and mint to adjust to new variables

    /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// @dev The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    /// @param _assets The amount of assets (=ETH).
    /// @param _rounding The rounding direction.
    function _convertToShares(uint256 _assets, Math.Rounding _rounding) 
        internal view 
        returns (uint256) 
    {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) return _assets;

        // deltaynETH = (1 - exchangeAdjustmentRate) * (ynETHSupply / totalControlled) * ethAmount
        //  If `(1 - exchangeAdjustmentRate) * ethAmount * ynETHSupply < totalControlled` this will be 0.
        
        // Can only happen in bootstrap phase if `totalControlled` and `ynETHSupply` could be manipulated
        // independently. That should not be possible.
        return Math.mulDiv(
            _assets,
            totalSupply() * uint256(BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalAssets() * uint256(BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }

    /*************************************\
    |                                     |
    | View functions also used internally |
    |                                     |
    \*************************************/

    /// @notice Calculates the amount of shares to be minted for a given deposit.
    /// @param assets The amount of assets to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(uint256 assets) 
        public view
        returns (uint256) 
    {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Retrieve the total number of assets (=ynETH).
    /// @return total The total amount of assets (=ynETH).
    function totalAssets() 
        public view 
        returns (uint256 total) 
    {
        // The total amount of allocated ETH for deposits, pending to be processed.
        total += totalDeposited;
        // The total ETH sent to the beacon chain (deposited into the ETH2Deposit contract)
        total += totalDepositedInValidators();
    }

    /// @notice Retrieve the total amount of ETH deposited by validators that are registered in the StakingNodes.
    /// @return totalDeposited The total amount deposited by validators.
    function totalDepositedInValidators() 
        public view
        returns (uint256 totalDeposited) 
    {
        IStakingNode[] memory nodes = stakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            totalDeposited += nodes[i].getETHBalance();
        }
    }

    /******************************\
    |                              |
    |      Fallback functions      |
    |                              |
    \******************************/

    /// @notice Accept ETH from the StakingNodesManager contract.
    /// @dev Only callable by the StakingNodesManager contract.
    /// @dev This happens when the StakingNodeManager.processWithdrawnETH function transfers
    ///      ETH to this ynETH contract.
    receive() 
        external payable 
        onlyStakingNodesManagerOrRewardsDistributor
    {
        totalDeposited += msg.value;
        emit YnEth_EthReceived(msg.sender, msg.value);
    }

    //@audit does this even work or is necessary?!
    /// @notice Disable the regular fallback function with a custom error.
    fallback() 
        external payable 
    {
        revert YnEth_DirectETHDepositsNotAllowed();
    }

    /******************************\
    |                              |
    |           Modifiers          |
    |                              |
    \******************************/

    /// @notice Ensures that the deposits are currently not paused.
    modifier whenDepositsNotPaused {
        if (depositsPaused) {
            revert YnEth_DepositsPaused();
        }
        _;    
    }

    /// @notice Ensure that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert YnEth_ZeroAddress();
        }
        _;
    }

     /// @notice Ensure the caller is the StakingNodeManager contract
    modifier onlyStakingNodesManager() {
        if (msg.sender != address(stakingNodesManager)) {
            revert YnEth_CallerNotStakingNodeManager(
                address(stakingNodesManager),
                msg.sender
            );
        }
        _;
    }

    /// @notice Ensure the caller is the RewardsDistributor or StakingNodesManager contract
    modifier onlyStakingNodesManagerOrRewardsDistributor() {
        if (msg.sender != address(rewardsDistributor) &&
            msg.sender != address(stakingNodesManager))
         {
            revert YnEth_CallerNotRewardsDistributorOrStakingNodesManager(
                address(rewardsDistributor),
                address(stakingNodesManager),
                msg.sender
            );
        }
        _;
    }
}
