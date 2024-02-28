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

interface IynLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
    event AssetRetrieved(IERC20 asset, uint256 amount, uint256 nodeId, address sender);
    event LSDStakingNodeCreated(uint nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint maxNodeCount);
}

contract ynLSD is IynLSD, ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IynLSDEvents {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 token);
    error ZeroAmount();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant LSD_RESTAKING_MANAGER_ROLE = keccak256("LSD_RESTAKING_MANAGER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    YieldNestOracle oracle;
    IStrategyManager public strategyManager;
        
    UpgradeableBeacon private upgradeableBeacon;

    mapping(IERC20 => IStrategy) public strategies;
    mapping(IERC20 => uint) public depositedBalances;

    IERC20[] public tokens;

    uint public exchangeAdjustmentRate;

    ILSDStakingNode[] public nodes;
    uint public maxNodeCount;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    struct Init {
        IERC20[] tokens;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        YieldNestOracle oracle;
        uint exchangeAdjustmentRate;
        uint maxNodeCount;
        address admin;
        address stakingAdmin;
        address lsdRestakingManager;
    }

    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(LSD_RESTAKING_MANAGER_ROLE, init.lsdRestakingManager);

        for (uint i = 0; i < init.tokens.length; i++) {
            tokens.push(init.tokens[i]);
            strategies[init.tokens[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        oracle = init.oracle;
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
        maxNodeCount = init.maxNodeCount;
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
        int256 assetPriceInETH = oracle.getLatestPrice(address(asset));
        uint256 assetAmountInETH = uint256(assetPriceInETH) * amount / 1e18; // Assuming price is in 18 decimal places

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
            totalSupply() * uint256(_BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalAssets() * uint256(_BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }

    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the tokens in the contract, gets the latest price for each token from the oracle, 
     * multiplies it with the balance of the token and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint) {
        uint total = 0;

        uint[] memory depositedBalances = getTotalAssets();
        for (uint i = 0; i < tokens.length; i++) {
            int256 price = oracle.getLatestPrice(address(tokens[i]));
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
    function convertToShares(IERC20 asset, uint amount) external view returns(uint shares) {
        IStrategy strategy = strategies[asset];
        if(address(strategy) != address(0)){
           int256 tokenPriceInETH = oracle.getLatestPrice(address(asset));
           uint256 tokenAmountInETH = uint256(tokenPriceInETH) * amount / 1e18;
           shares = _convertToShares(tokenAmountInETH, Math.Rounding.Floor);
        } else {
            revert UnsupportedAsset(asset);
        }
    }

    function getTotalAssets()
        public
        view
        returns (uint[] memory assetBalances)
    {
        assetBalances = new uint[](tokens.length);
        IStrategy[] memory assetStrategies = new IStrategy[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            assetStrategies[i] = strategies[tokens[i]];
        }

        uint256 nodeCount = nodes.length;
        for (uint256 i; i < nodeCount; i++ ) {
            
            ILSDStakingNode node = nodes[i];
            for (uint j = 0; j < tokens.length; j++) {
                
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

    function createLSDStakingNode() public returns (ILSDStakingNode) {

        require(address(upgradeableBeacon) != address(0), "LSDStakingNode: upgradeableBeacon is not set");
        require(nodes.length < maxNodeCount, "StakingNodesManager: nodes.length >= maxNodeCount");

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        ILSDStakingNode node = ILSDStakingNode(payable(proxy));

        uint nodeId = nodes.length;

        node.initialize(
            ILSDStakingNode.Init(IynLSD(address(this)), nodeId)
        );
        nodes.push(node);

        emit LSDStakingNodeCreated(nodeId, address(node));

        return node;
    }

    function registerStakingNodeImplementationContract(address _implementationContract) onlyRole(STAKING_ADMIN_ROLE) public {

        require(_implementationContract != address(0), "StakingNodesManager:No zero address");
        require(address(upgradeableBeacon) == address(0), "StakingNodesManager: Implementation already exists");

        upgradeableBeacon = new UpgradeableBeacon(_implementationContract, address(this));     
    }

    function upgradeStakingNodeImplementation(address _implementationContract, bytes memory callData) public onlyRole(STAKING_ADMIN_ROLE) {

        require(address(upgradeableBeacon) != address(0), "StakingNodesManager: A Staking node implementation has never been registered");
        require(_implementationContract != address(0), "StakingNodesManager: Implementation cannot be zero address");
        upgradeableBeacon.upgradeTo(_implementationContract);

        if (callData.length == 0) {
            // no function to initialize with
            return;
        }
        // reinitialize all nodes
        for (uint i = 0; i < nodes.length; i++) {
            (bool success, ) = address(nodes[i]).call(callData);
            require(success, "ynLSD: Failed to call method on upgraded node");
        }
    }

    /// @notice Sets the maximum number of staking nodes allowed
    /// @param _maxNodeCount The maximum number of staking nodes
    function setMaxNodeCount(uint _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    function hasLSDRestakingManagerRole(address account) external returns (bool) {
        return hasRole(LSD_RESTAKING_MANAGER_ROLE, account);
    }

    function retrieveAsset(uint nodeId, IERC20 asset, uint256 amount) external {
        require(address(nodes[nodeId]) == msg.sender, "msg.sender does not match nodeId");

        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert UnsupportedAsset(asset);
        }

        IERC20(asset).transfer(msg.sender, amount);
        emit AssetRetrieved(asset, amount, nodeId, msg.sender);
    }
}
