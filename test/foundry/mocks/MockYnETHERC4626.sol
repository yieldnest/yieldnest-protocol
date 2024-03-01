// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IDepositPool} from "../../../src/interfaces/IDepositPool.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IRewardsDistributor} from "../../../src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";

import {IynETH} from "../../../src/interfaces/IynETH.sol";
import {IDepositContract} from "../../../src/external/ethereum/IDepositContract.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../../../src/interfaces/IOracle.sol";
import "../../../src/external/tokens/IWETH.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "forge-std/console.sol";


// This mock contract simulates ynETH upgraded to ERC4626, with an underlying Ethereum pegged token, 
// referred to as Nest ETH (nETH). This model draws inspiration from sfrxETH/frxETH.
contract MockYnETHERC4626 is IynETH, AccessControlUpgradeable, ERC4626Upgradeable {

    /// @notice Emitted when a user stakes ETH and receives ynETH.
    /// @param staker The address of the user staking ETH.
    /// @param ethAmount The amount of ETH staked.
    /// @param ynETHAmount The amount of ynETH received.
    event Staked(address indexed staker, uint256 ethAmount, uint256 ynETHAmount);
    event DepositETHPausedUpdated(bool isPaused);
    event ExchangeAdjustmentRateUpdated(uint256 newRate);

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error MinimumStakeBoundNotSatisfied();
    error StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error Paused();
    error ValueOutOfBounds(uint value);


    IStakingNodesManager public stakingNodesManager;
    IRewardsDistributor public rewardsDistributor;
    uint public allocatedETHForDeposits;
    bool public depositsPaused;
    // Storage variables


    /// @dev The value is in basis points (1/10000).
    uint public exchangeAdjustmentRate;

    uint public totalDepositedInPool;

    struct ReInit {

        IERC20 underlyingAsset;
    }

    /// @notice Reinitializes the mock contract with new parameters.
    /// @param reinit The initialization parameters.
    function reinitialize(ReInit memory reinit) external reinitializer(2) {
         __ERC4626_init(reinit.underlyingAsset);

         
    }

    function deposit(uint assets, address receiver) public override returns (uint shares) {

        if (depositsPaused) {
            console.log("System is paused");
            revert Paused();
        }
    
        require(assets > 0, "assets == 0");


        shares = previewDeposit(assets);

        _mint(receiver, shares);

        totalDepositedInPool += assets;
        emit Deposit(msg.sender, receiver, assets, shares);
    }


    /// DUPLICATES from ynETH.sol

     /// @notice Converts from ynETH to ETH using the current exchange rate.
    /// The exchange rate is given by the total supply of ynETH and total ETH controlled by the protocol.
    function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view override returns (uint256) {
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
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function totalAssets() public view override returns (uint) {
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

    function updateDepositsPaused(bool isPaused) external onlyRole(PAUSER_ROLE) {
        depositsPaused = isPaused;
        emit DepositETHPausedUpdated(depositsPaused);
    }

    function setExchangeAdjustmentRate(uint256 newRate) external onlyStakingNodesManager {
        if (newRate > _BASIS_POINTS_DENOMINATOR) {
            revert ValueOutOfBounds(newRate);
        }
        exchangeAdjustmentRate = newRate;
        emit ExchangeAdjustmentRateUpdated(newRate);
    }
    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS   ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Caller is not the stakingNodesManager");
        _;
    }

}
