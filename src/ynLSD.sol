// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "./external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
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

    error UnsupportedAsset(IERC20 asset);
    error ZeroAmount();
    error ExchangeAdjustmentRateOutOfBounds(uint256 exchangeAdjustmentRate);
    error ZeroAddress();
    error BeaconImplementationAlreadyExists();
    error NoBeaconImplementationExists();
    error TooManyStakingNodes(uint256 maxNodeCount);
    error NotLSDStakingNode(address sender, uint256 nodeId);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant LSD_RESTAKING_MANAGER_ROLE = keccak256("LSD_RESTAKING_MANAGER_ROLE");
    bytes32 public constant LSD_STAKING_NODE_CREATOR_ROLE = keccak256("LSD_STAKING_NODE_CREATOR_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    YieldNestOracle  public oracle;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    UpgradeableBeacon public upgradeableBeacon;

    /// @notice Mapping of ERC20 tokens to their corresponding EigenLayer strategy contracts.
    mapping(IERC20 => IStrategy) public strategies;

    /// @notice List of supported ERC20 asset contracts.
    IERC20[] public assets;

    uint256 public exchangeAdjustmentRate;
    
    /**
     * @notice Array of LSD Staking Node contracts.
     * @dev These nodes are crucial for the delegation process within the YieldNest protocol. Each node represents a unique staking entity
     * that can delegate LSD tokens to various operators for yield optimization. 
     */
    ILSDStakingNode[] public nodes;
    uint256 public maxNodeCount;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
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

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            assets.push(init.assets[i]);
            strategies[init.assets[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        oracle = init.oracle;

        if (init.exchangeAdjustmentRate > BASIS_POINTS_DENOMINATOR) {
            revert ExchangeAdjustmentRateOutOfBounds(init.exchangeAdjustmentRate);
        }
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
        maxNodeCount = init.maxNodeCount;

        _setTransfersPaused(true);  // transfers are initially paused
        _updatePauseWhitelist(init.pauseWhitelist, true);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSITS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits a specified amount of an asset into the contract and mints shares to the receiver.
     * @dev This function first checks if the asset is supported, then converts the asset amount to ETH equivalent,
     * calculates the shares to be minted based on the ETH value, mints the shares to the receiver, and finally
     * transfers the asset from the sender to the contract. Emits a Deposit event upon success.
     * @param asset The ERC20 asset to be deposited.
     * @param amount The amount of the asset to be deposited.
     * @param receiver The address to receive the minted shares.
     * @return shares The amount of shares minted to the receiver.
     */
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

        // Convert the value of the asset deposited to ETH
        uint256 assetAmountInETH = convertToETH(asset, amount);
        // Calculate how many shares to be minted using the same formula as ynETH
        shares = _convertToShares(assetAmountInETH, Math.Rounding.Floor);

        // Mint the calculated shares to the receiver 
        _mint(receiver, shares);

        // Transfer assets in after shares are computed since _convertToShares relies on totalAssets
        // which inspects asset.balanceOf(address(this))
        asset.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, receiver, amount, shares);
    }

    /**
     * @dev Converts an ETH amount to shares based on the current exchange rate and specified rounding method.
     * If it's the first stake (bootstrap phase), uses a 1:1 exchange rate. Otherwise, calculates shares based on
     * the formula: deltaynETH = (1 - exchangeAdjustmentRate) * (ynETHSupply / totalControlled) * ethAmount.
     * This calculation can result in 0 during the bootstrap phase if `totalControlled` and `ynETHSupply` could be
     * manipulated independently, which should not be possible.
     * @param ethAmount The amount of ETH to convert to shares.
     * @param rounding The rounding method to use for the calculation.
     * @return The number of shares equivalent to the given ETH amount.
     */
    function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the bootstrap call, not totalAssets
        if (totalSupply() == 0) {
            return ethAmount;
        }

        // deltaynETH = (1 - exchangeAdjustmentRate) * (ynETHSupply / totalControlled) * ethAmount
        // If `(1 - exchangeAdjustmentRate) * ethAmount * ynETHSupply < totalControlled` this will be 0.
        
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
    /// @param asset The asset to be deposited.
    /// @param amount The amount of asset to be deposited.
    /// @return The amount of shares to be minted.
    function previewDeposit(IERC20 asset, uint256 amount) public view virtual returns (uint256) {
        return convertToShares(asset, amount);
    }

    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the assets in the contract, gets the latest price for each asset from the oracle, 
     * multiplies it with the balance of the asset and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint256) {
        uint256 total = 0;

        uint256[] memory depositedBalances = getTotalAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balanceInETH = convertToETH(assets[i], depositedBalances[i]);
            total += balanceInETH;
        }
        return total;
    }

   /**
     * @notice Converts a given amount of a specific asset to shares
     * @param asset The ERC-20 asset to be converted
     * @param amount The amount of the asset to be converted
     * @return shares The equivalent amount of shares for the given amount of the asset
     */
    function convertToShares(IERC20 asset, uint256 amount) public view returns(uint256 shares) {
        IStrategy strategy = strategies[asset];
        if(address(strategy) != address(0)){
           uint256 assetAmountInETH = convertToETH(asset, amount);
           shares = _convertToShares(assetAmountInETH, Math.Rounding.Floor);
        } else {
            revert UnsupportedAsset(asset);
        }
    }

    /**
     * @notice Retrieves the total balances of all assets managed by the contract, both held directly and managed through strategies.
     * @dev This function aggregates the balances of each asset held directly by the contract and in each LSDStakingNode, 
     * including those managed by strategies associated with each asset.
     * @return assetBalances An array of the total balances for each asset, indexed in the same order as the `assets` array.
     */
    function getTotalAssets()
        public
        view
        returns (uint256[] memory assetBalances)
    {
        assetBalances = new uint256[](assets.length);
        IStrategy[] memory assetStrategies = new IStrategy[](assets.length);
        
        // First, add balances for funds held directly in ynLSD.
        for (uint256 i = 0; i < assets.length; i++) {
            assetStrategies[i] = strategies[assets[i]];

            // add balances for funds at rest in ynLSD
            uint256 balanceThis = assets[i].balanceOf(address(this));
            assetBalances[i] += balanceThis;
        }

        // Next, add balances contained in each LSDStakingNode, including those managed by strategies.
        uint256 nodeCount = nodes.length;
        for (uint256 i; i < nodeCount; i++ ) {
            
            ILSDStakingNode node = nodes[i];
            for (uint256 j = 0; j < assets.length; j++) {
                
                IERC20 asset = assets[i];
                uint256 balanceNode = asset.balanceOf(address(node));
                assetBalances[j] += balanceNode;

                uint256 strategyBalance = assetStrategies[j].userUnderlyingView((address(node)));
                assetBalances[j] += strategyBalance;
            }
        }
    }
    /**
     * @notice Converts the amount of a given asset to its equivalent value in ETH based on the latest price from the oracle.
     * @dev This function takes into account the decimal places of the asset to ensure accurate conversion.
     * @param asset The ERC20 token to be converted to ETH.
     * @param amount The amount of the asset to be converted.
     * @return The equivalent amount of the asset in ETH.
     */
    function convertToETH(IERC20 asset, uint amount) public view returns (uint256) {
        uint256 assetPriceInETH = oracle.getLatestPrice(address(asset));
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
        return assetDecimals < 18 || assetDecimals > 18
            ? assetPriceInETH * amount / (10 ** assetDecimals)
            : assetPriceInETH * amount / 1e18;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------
    /**
     * @notice Creates a new LSD Staking Node using the Upgradeable Beacon pattern.
     * @dev This function creates a new BeaconProxy instance pointing to the current implementation set in the upgradeableBeacon.
     * It initializes the staking node, adds it to the nodes array, and emits an event.
     * Reverts if the maximum number of staking nodes has been reached.
     * @return ILSDStakingNode The interface of the newly created LSD Staking Node.
     */
    function createLSDStakingNode()
        public
        notZeroAddress((address(upgradeableBeacon)))
        onlyRole(LSD_STAKING_NODE_CREATOR_ROLE)
        returns (ILSDStakingNode) {

        if (nodes.length >= maxNodeCount) {
            revert TooManyStakingNodes(maxNodeCount);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        ILSDStakingNode node = ILSDStakingNode(payable(proxy));

        uint256 nodeId = nodes.length;
        initializeLSDStakingNode(node);

        nodes.push(node);

        emit LSDStakingNodeCreated(nodeId, address(node));

        return node;
    }

    /**
     * @notice Initializes a newly created LSD Staking Node.
     * @dev This function checks the current initialized version of the node and performs initialization if it hasn't been done.
     * For future versions, additional conditional blocks should be added to handle version-specific initialization.
     * @param node The ILSDStakingNode instance to be initialized.
     */
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

    /**
     * @notice Registers a new LSD Staking Node implementation contract.
     * @dev This function sets a new implementation contract for the LSD Staking Node by creating a new UpgradeableBeacon.
     * It can only be called once to boostrap the first implementation.
     * @param _implementationContract The address of the new LSD Staking Node implementation contract.
     */
    function registerLSDStakingNodeImplementationContract(address _implementationContract)
        public
        onlyRole(STAKING_ADMIN_ROLE)
        notZeroAddress(_implementationContract) {

        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(_implementationContract, address(this));     
    }

    /**
     * @notice Upgrades the LSD Staking Node implementation to a new version.
     * @dev This function upgrades the implementation contract of the LSD Staking Nodes by setting a new implementation address in the upgradeable beacon.
     * It then reinitializes all existing staking nodes to ensure they are compatible with the new implementation.
     * This function can only be called by an account with the STAKING_ADMIN_ROLE.
     * @param _implementationContract The address of the new implementation contract.
     */
    function upgradeLSDStakingNodeImplementation(address _implementationContract)  
        public 
        onlyRole(STAKING_ADMIN_ROLE) 
        notZeroAddress(_implementationContract) {

        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }

        upgradeableBeacon.upgradeTo(_implementationContract);

        // Reinitialize all nodes to ensure compatibility with the new implementation.
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

    function hasLSDRestakingManagerRole(address account) external view returns (bool) {
        return hasRole(LSD_RESTAKING_MANAGER_ROLE, account);
    }

    /**
     * @notice Retrieves a specified amount of an asset from the staking node.
     * @dev Transfers the specified `amount` of `asset` to the caller, if the caller is the staking node.
     * Reverts if the caller is not the staking node or if the asset is not supported.
     * @param nodeId The ID of the staking node attempting to retrieve the asset.
     * @param asset The ERC20 token to be retrieved.
     * @param amount The amount of the asset to be retrieved.
     */
    function retrieveAsset(uint256 nodeId, IERC20 asset, uint256 amount) external {
        if (address(nodes[nodeId]) != msg.sender) {
            revert NotLSDStakingNode(msg.sender, nodeId);
        }

        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert UnsupportedAsset(asset);
        }

        IERC20(asset).safeTransfer(msg.sender, amount);
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
