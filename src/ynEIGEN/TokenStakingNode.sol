// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 eigenShares
    );
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
}

/**
 * @title Token Staking Node
 * @dev Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract TokenStakingNode is
    ITokenStakingNode,
    Initializable,
    ReentrancyGuardUpgradeable,
    ITokenStakingNodeEvents
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();
    error NotTokenStakingNodeOperator();
    error NotStrategyManager();
    error NotTokenStakingNodeDelegator();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    ITokenStakingNodesManager public override tokenStakingNodesManager;
    uint256 public nodeId;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(
        Init memory init
    )
        public
        notZeroAddress(address(init.tokenStakingNodesManager))
        initializer
    {
        __ReentrancyGuard_init();
        tokenStakingNodesManager = init.tokenStakingNodesManager;
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENLAYER DEPOSITS  -----------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits multiple assets into their respective strategies on Eigenlayer by retrieving them from tokenStakingNodesManager.
     * @dev Iterates through the provided arrays of assets and amounts, depositing each into its corresponding strategy.
     * @param assets An array of IERC20 tokens to be deposited.
     * @param amounts An array of amounts corresponding to each asset to be deposited.
     */
    function depositAssetsToEigenlayer(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external nonReentrant onlyYieldNestStrategyManager {
        IStrategyManager strategyManager = tokenStakingNodesManager
            .strategyManager();

        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];

            asset.forceApprove(address(strategyManager), amount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(
                IStrategy(strategy),
                asset,
                amount
            );
            emit DepositToEigenlayer(asset, strategy, amount, eigenShares);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DELEGATION  --------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates the staking operation to a specified operator.
     * @param operator The address of the operator to whom the staking operation is being delegated.
     */
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) public virtual onlyDelegator {
        IDelegationManager delegationManager = tokenStakingNodesManager
            .delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        emit Delegated(operator, 0);
    }

    /**
     * @notice Undelegates the staking operation.
     */
    function undelegate() public override onlyDelegator {
        IDelegationManager delegationManager = IDelegationManager(
            address(tokenStakingNodesManager.delegationManager())
        );
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(
            address(this)
        );

        emit Undelegated(withdrawalRoots);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyOperator() {
        if (
            !tokenStakingNodesManager.hasTokenStakingNodeOperatorRole(msg.sender)
        ) {
            revert NotTokenStakingNodeOperator();
        }
        _;
    }

    modifier onlyDelegator() {
        if (!tokenStakingNodesManager.hasTokenStakingNodeDelegatorRole(msg.sender)) {
            revert NotTokenStakingNodeDelegator();
        }
        _;
    }

    modifier onlyYieldNestStrategyManager() {
        if (!tokenStakingNodesManager.hasYieldNestStrategyManagerRole(msg.sender)) {
            revert NotStrategyManager();
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
