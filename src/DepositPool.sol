// SPDX-License-Identifier: MIT
import {IDepositPool} from "./interfaces/IDepositPool.sol";
import {IynETH} from "./interfaces/IynETH.sol";
import {IDepositContract} from "./interfaces/IDepositContract.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface StakingEvents {
    /// @notice Emitted when a user stakes ETH and receives mETH.
    /// @param staker The address of the user staking ETH.
    /// @param ethAmount The amount of ETH staked.
    /// @param mETHAmount The amount of mETH received.
    event Staked(address indexed staker, uint256 ethAmount, uint256 mETHAmount);

}
 
contract DepositPool is Initializable, AccessControlUpgradeable, IDepositPool, StakingEvents {

    // Errors.
    error DoesNotReceiveETH();
    error InvalidConfiguration();
    error MaximumValidatorDepositExceeded();
    error MaximumynETHSupplyExceeded();
    error MinimumStakeBoundNotSatisfied();
    error MinimumUnstakeBoundNotSatisfied();
    error MinimumValidatorDepositNotSatisfied();
    error NotEnoughDepositETH();
    error NotEnoughUnallocatedETH();
    error NotReturnsAggregator();
    error NotUnstakeRequestsManager();
    error Paused();
    error PreviouslyUsedValidator();
    error ZeroAddress();
    error InvalidDepositRoot(bytes32);
    error StakeBelowMinimumynETHAmount(uint256 methAmount, uint256 expectedMinimum);
    error UnstakeBelowMinimumETHAmount(uint256 ethAmount, uint256 expectedMinimum);
    error InvalidWithdrawalCredentialsWrongLength(uint256);
    error InvalidWithdrawalCredentialsNotETH1(bytes12);
    error InvalidWithdrawalCredentialsWrongAddress(address);


    IynETH public ynETH;
    IDepositContract public depositContract;
    address public stakingNodesManager;
    // Storage variables
    uint256 public minimumStakeBound;

    /// As the adjustment is applied to the exchange rate, the result is reflected in any user interface which shows the
    /// amount of mETH received when staking, meaning there is no surprise for users when staking or unstaking.
    /// @dev The value is in basis points (1/10000).
    uint16 public exchangeAdjustmentRate;

    /// @dev A basis point (often denoted as bp, 1bp = 0.01%) is a unit of measure used in finance to describe
    /// the percentage change in a financial instrument. This is a constant value set as 10000 which represents
    /// 100% in basis point terms.
    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        IynETH ynETH;
        IDepositContract depositContract;
        address stakingNodesManager;
    }

    constructor() {
        // TODO; re-enable this
        // _disableInitializers();
    }


        /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);


        ynETH = init.ynETH;
        depositContract = init.depositContract;
        stakingNodesManager = init.stakingNodesManager;

        minimumStakeBound = 0.00001 ether;
    }


    function deposit(uint256 minynETHAmount) external payable {
 

        if (msg.value < minimumStakeBound) {
            revert MinimumStakeBoundNotSatisfied();
        }

        uint256 ynETHMintAmount = ethToynETH(msg.value);
        if (ynETHMintAmount < minynETHAmount) {
            revert StakeBelowMinimumynETHAmount(ynETHMintAmount, minynETHAmount);
        }

        emit Staked(msg.sender, msg.value, ynETHMintAmount);
        ynETH.mint(msg.sender, ynETHMintAmount);
    }    

    /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    function ethToynETH(uint256 ethAmount) public view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Using `ynETH.totalSupply` over `totalControlled` to check if the protocol is in its bootstrap phase since
        // the latter can be manipulated, for example by transferring funds to the `ExecutionLayerReturnsReceiver`, and
        // therefore be non-zero by the time the first stake is made
        if (ynETH.totalSupply() == 0) {
            return ethAmount;
        }

        // deltaynETH = (1 - exchangeAdjustmentRate) * (ynETHSupply / totalControlled) * ethAmount
        // This rounds down to zero in the case of `(1 - exchangeAdjustmentRate) * ethAmount * ynETHSupply <
        // totalControlled`.
        // While this scenario is theoretically possible, it can only be realised feasibly during the protocol's
        // bootstrap phase and if `totalControlled` and `ynETHSupply` can be changed independently of each other. Since
        // the former is permissioned, and the latter is not permitted by the protocol, this cannot be exploited by an
        // attacker.
        return Math.mulDiv(
            ethAmount,
            ynETH.totalSupply() * uint256(_BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalControlled() * uint256(_BASIS_POINTS_DENOMINATOR)
        );
    }

        /// @notice The total amount of ETH controlled by the protocol.
    /// @dev Sums over the balances of various contracts and the beacon chain information from the oracle.
    function totalControlled() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawETH(uint ethAmount) public {
        require(msg.sender == stakingNodesManager, "Only StakingNodesManager can call this function");
        require(address(this).balance >= ethAmount, "Insufficient balance");
        payable(msg.sender).transfer(ethAmount);
    }

}
