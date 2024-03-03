// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IynLSD} from "./interfaces/IynLSD.sol";
import {ILSDStakingNode} from "./interfaces/ILSDStakingNode.sol";
import {YieldNestOracle} from "./YieldNestOracle.sol";
import {ynBase} from "./ynBase.sol";

interface IynLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
    event AssetRetrieved(IERC20 asset, uint256 amount, uint256 nodeId, address sender);
    event LSDStakingNodeCreated(uint256 nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint256 maxNodeCount);
}

contract ynLSD is IynLSD, ynBase, ReentrancyGuardUpgradeable, IynLSDEvents {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 token);
    error ZeroAmount();
    error ExchangeAdjustmentRateOutOfBounds(uint256 exchangeAdjustmentRate);
    error ZeroAddress();
    error BeaconImplementationAlreadyExists();
    error NoBeaconImplementationExists();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant LSD_RESTAKING_MANAGER_ROLE = keccak256("LSD_RESTAKING_MANAGER_ROLE");
    bytes32 public constant LSD_STAKING_NODE_CREATOR_ROLE = keccak256("LSD_STAKING_NODE_CREATOR_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant BASIS_POINTS_DENOMINATOR = 10_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    YieldNestOracle  public oracle;
    IStrategyManager public strategyManager;
        
    UpgradeableBeacon public upgradeableBeacon;

    mapping(IERC20 => IStrategy) public strategies;

    IERC20[] public tokens;

    uint256 public exchangeAdjustmentRate;

    ILSDStakingNode[] public nodes;
    uint256 public maxNodeCount;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        IERC20[] tokens;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        YieldNestOracle oracle;
        uint256 exchangeAdjustmentRate;
        uint256 maxNodeCount;
        address admin;
        address pauser;
        address stakingAdmin;
        address lsdRestakingManager;
        address lsdStakingNodeCreatorRole;
        address[] pauseWhitelist;
    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.strategyManager))
        notZeroAddress(address(init.oracle))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.stakingAdmin))
        notZeroAddress(address(init.lsdRestakingManager))
        notZeroAddress(init.lsdStakingNodeCreatorRole)
        initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __ynBase_init("ynLSD", "ynLSD");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(LSD_RESTAKING_MANAGER_ROLE, init.lsdRestakingManager);
        _grantRole(LSD_STAKING_NODE_CREATOR_ROLE, init.lsdStakingNodeCreatorRole);
        _grantRole(PAUSER_ROLE, init.pauser);

        for (uint256 i = 0; i < init.tokens.length; i++) {
            if (address(init.tokens[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            tokens.push(init.tokens[i]);
            strategies[init.tokens[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        oracle = init.oracle;

        if (init.exchangeAdjustmentRate > BASIS_POINTS_DENOMINATOR) {
            revert ExchangeAdjustmentRateOutOfBounds(init.exchangeAdjustmentRate);
        }
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
        maxNodeCount = init.maxNodeCount;

        _setTransfersPaused(true);  // transfers are initially paused
        _addToPauseWhitelist(init.pauseWhitelist);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external nonReentrant returns (uint256 shares) {

        IStrategy strategy = strategies[asset];
        if(address(strategy) == address(0x0)){
            revert UnsupportedAsset(asset);
        }

        if (amount == 0) {
            revert ZeroAmount();
        }
        asset.safeTransferFrom(msg.sender, address(this), amount);
         // Convert the value of the asset deposited to ETH
        uint256 assetPriceInETH = oracle.getLatestPrice(address(asset));
        uint256 assetAmountInETH = assetPriceInETH * amount / 1e18; // Assuming price is in 18 decimal places

        // Calculate how many shares to be minted using the same formula as ynETH
        shares = _convertToShares(assetAmountInETH, Math.Rounding.Floor);

        // Mint the calculated shares to the receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares);
    }


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

    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the tokens in the contract, gets the latest price for each token from the oracle, 
     * multiplies it with the balance of the token and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint256) {
        uint256 total = 0;

        uint256[] memory depositedBalances = getTotalAssets();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 price = oracle.getLatestPrice(address(tokens[i]));
            uint256 balance = depositedBalances[i];
            total += uint256(price) * balance / 1e18;
        }
        return total;
    }

   /**
     * @notice Converts a given amount of a specific token to shares
     * @param asset The ERC-20 token to be converted
     * @param amount The amount of the token to be converted
     * @return shares The equivalent amount of shares for the given amount of the token
     */
    function convertToShares(IERC20 asset, uint256 amount) external view returns(uint256 shares) {
        IStrategy strategy = strategies[asset];
        if(address(strategy) != address(0)){
           uint256 tokenPriceInETH = oracle.getLatestPrice(address(asset));
           uint256 tokenAmountInETH = tokenPriceInETH * amount / 1e18;
           shares = _convertToShares(tokenAmountInETH, Math.Rounding.Floor);
        } else {
            revert UnsupportedAsset(asset);
        }
    }

    function getTotalAssets()
        public
        view
        returns (uint256[] memory assetBalances)
    {
        assetBalances = new uint256[](tokens.length);
        IStrategy[] memory assetStrategies = new IStrategy[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            assetStrategies[i] = strategies[tokens[i]];
        }

        uint256 nodeCount = nodes.length;
        for (uint256 i; i < nodeCount; i++ ) {
            
            ILSDStakingNode node = nodes[i];
            for (uint256 j = 0; j < tokens.length; j++) {
                
                IERC20 asset = tokens[i];
                assetBalances[j] += asset.balanceOf(address(this));
                assetBalances[j] += asset.balanceOf(address(node));
                assetBalances[j] += assetStrategies[j].userUnderlyingView((address(node)));
            }
        }
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    function createLSDStakingNode()
        public
        onlyRole(LSD_STAKING_NODE_CREATOR_ROLE)
        returns (ILSDStakingNode) {

        require(address(upgradeableBeacon) != address(0), "LSDStakingNode: upgradeableBeacon is not set");
        require(nodes.length < maxNodeCount, "StakingNodesManager: nodes.length >= maxNodeCount");

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        ILSDStakingNode node = ILSDStakingNode(payable(proxy));

        uint256 nodeId = nodes.length;
        initializeLSDStakingNode(node);

        nodes.push(node);

        emit LSDStakingNodeCreated(nodeId, address(node));

        return node;
    }

    function initializeLSDStakingNode(ILSDStakingNode node) virtual internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             uint256 nodeId = nodes.length;
             node.initialize(
               ILSDStakingNode.Init(IynLSD(address(this)), nodeId)
             );

             // update version to latest
             initializedVersion = node.getInitializedVersion();
         }

         // NOTE: for future versions add additional if clauses that initialize the node 
         // for the next version while keeping the previous initializers
    }

    function registerLSDStakingNodeImplementationContract(address _implementationContract)
        onlyRole(STAKING_ADMIN_ROLE)
        notZeroAddress(_implementationContract)
        public{

        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(_implementationContract, address(this));     
    }

    function upgradeLSDStakingNodeImplementation(address _implementationContract)   
        onlyRole(STAKING_ADMIN_ROLE) 
        notZeroAddress(_implementationContract)
        public {

        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }

        upgradeableBeacon.upgradeTo(_implementationContract);

        // reinitialize all nodes
        for (uint256 i = 0; i < nodes.length; i++) {
            initializeLSDStakingNode(nodes[i]);
        }
    }

    /// @notice Sets the maximum number of staking nodes allowed
    /// @param _maxNodeCount The maximum number of staking nodes
    function setMaxNodeCount(uint256 _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    function hasLSDRestakingManagerRole(address account) external returns (bool) {
        return hasRole(LSD_RESTAKING_MANAGER_ROLE, account);
    }

    function retrieveAsset(uint256 nodeId, IERC20 asset, uint256 amount) external {
        require(address(nodes[nodeId]) == msg.sender, "msg.sender does not match nodeId");

        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert UnsupportedAsset(asset);
        }

        IERC20(asset).transfer(msg.sender, amount);
        emit AssetRetrieved(asset, amount, nodeId, msg.sender);
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
}
