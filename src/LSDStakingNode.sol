// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILSDStakingNode} from "./interfaces/ILSDStakingNode.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IynLSD} from "./interfaces/IynLSD.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "./external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";

interface ILSDStakingNodeEvents {
    event DepositToEigenlayer(IERC20 indexed asset, IStrategy indexed strategy, uint256 amount, uint256 eigenShares);
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(address indexed operator);
}

/**
 * @title LSD Staking Node
 * @dev Implements staking node functionality for LSD tokens, enabling LSD staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract LSDStakingNode is ILSDStakingNode, Initializable, ReentrancyGuardUpgradeable, ILSDStakingNodeEvents {

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 asset);
    error ZeroAmount();
    error ZeroAddress();
    error NotLSDRestakingManager();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynLSD public ynLSD;
    uint256 public nodeId;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.ynLSD))
        initializer {
        __ReentrancyGuard_init();
        ynLSD = init.ynLSD;
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENLAYER DEPOSITS  -----------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits multiple assets into their respective strategies on Eigenlayer by retrieving them from ynLSD.
     * @dev Iterates through the provided arrays of assets and amounts, depositing each into its corresponding strategy.
     * @param assets An array of IERC20 tokens to be deposited.
     * @param amounts An array of amounts corresponding to each asset to be deposited.
     */
    function depositAssetsToEigenlayer(
        IERC20[] memory assets,
        uint256[] memory amounts
    )
        external
        nonReentrant
        onlyLSDRestakingManager
    {
        IStrategyManager strategyManager = ynLSD.strategyManager();

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = ynLSD.strategies(asset);

            uint256 balanceBefore = asset.balanceOf(address(this));
            ynLSD.retrieveAsset(nodeId, asset, amount);
            uint256 balanceAfter = asset.balanceOf(address(this));
            uint256 retrievedAmount = balanceAfter - balanceBefore;

            asset.forceApprove(address(strategyManager), retrievedAmount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(IStrategy(strategy), asset, retrievedAmount);
            emit DepositToEigenlayer(asset, strategy, retrievedAmount, eigenShares);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DELEGATION  --------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates the staking operation to a specified operator.
     * @param operator The address of the operator to whom the staking operation is being delegated.
     */
    function delegate(address operator) public virtual onlyLSDRestakingManager {

        IDelegationManager delegationManager = ynLSD.delegationManager();
        delegationManager.delegateTo(operator);

        emit Delegated(operator, 0);
    }

    /**
     * @notice Undelegates the staking operation from the current operator.
     * @dev Retrieves the current operator by calling `delegatedTo` on the DelegationManager for event logging.
     */
    function undelegate() public virtual onlyLSDRestakingManager {
        
        IDelegationManager delegationManager = ynLSD.delegationManager();
        address operator = delegationManager.delegatedTo(address(this));
        
        IStrategyManager strategyManager = ynLSD.strategyManager();
        strategyManager.undelegate();

        emit Undelegated(operator);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyLSDRestakingManager() {
        if (!ynLSD.hasLSDRestakingManagerRole(msg.sender)) {
            revert NotLSDRestakingManager();
        }
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BEACON IMPLEMENTATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
      Beacons slot value is defined here:
      https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
     */
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    /// @notice Retrieve the version number of the highest/newest initialize
    ///         function that was executed.
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
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
