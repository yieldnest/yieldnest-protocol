// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IynLSD} from "./interfaces/IynLSD.sol";
import {YieldNestOracle} from "./YieldNestOracle.sol";

interface IynLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares, uint256 eigenShares);
}

contract ynLSD is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IynLSDEvents {
    using SafeERC20 for IERC20;

    error UnsupportedToken(IERC20 token);
    error ZeroAmount();

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    YieldNestOracle oracle;
    IStrategyManager public strategyManager;

    mapping(IERC20 => IStrategy) public strategies;
    mapping(IERC20 => uint) public depositedBalances;

    IERC20[] public tokens;

    uint public exchangeAdjustmentRate;

    struct Init {
        IERC20[] tokens;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        YieldNestOracle oracle;
        uint exchangeAdjustmentRate;
    }

    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        for (uint i = 0; i < init.tokens.length; i++) {
            tokens.push(init.tokens[i]);
            strategies[init.tokens[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        oracle = init.oracle;
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
    }

    function deposit(
        IERC20 token,
        uint256 amount,
        address receiver
    ) external nonReentrant returns (uint256 shares) {

        IStrategy strategy = strategies[token];
        if(address(strategy) == address(0x0)){
            revert UnsupportedToken(token);
        }

        if (amount == 0) {
            revert ZeroAmount();
        }
        token.safeTransferFrom(msg.sender, address(this), amount);

        token.approve(address(strategyManager), amount);

        uint eigenShares = strategyManager.depositIntoStrategy(
                strategy,
                token,
                amount
            );

        depositedBalances[token] += amount;

         // Convert the value of the token deposited to ETH
        int256 tokenPriceInETH = oracle.getLatestPrice(address(token));
        uint256 tokenAmountInETH = uint256(tokenPriceInETH) * amount / 1e18; // Assuming price is in 18 decimal places

        // Calculate how many shares to be minted using the same formula as ynETH
        shares = _convertToShares(tokenAmountInETH, Math.Rounding.Floor);

        // Mint the calculated shares to the receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares, eigenShares);
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


   // ==================================== VIEW FUNCTIONS =========================================
    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the tokens in the contract, gets the latest price for each token from the oracle, 
     * multiplies it with the balance of the token and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint) {
        uint total = 0;
        for (uint i = 0; i < tokens.length; i++) {
            int256 price = oracle.getLatestPrice(address(tokens[i]));
            uint256 balance = depositedBalances[tokens[i]];
            total += uint256(price) * balance / 1e18;
        }
        return total;
    }

   /**
     * @notice Converts a given amount of a specific token to shares
     * @param token The ERC-20 token to be converted
     * @param amount The amount of the token to be converted
     * @return shares The equivalent amount of shares for the given amount of the token
     */
    function convertToShares(IERC20 token, uint amount) external view returns(uint shares) {
        IStrategy strategy = strategies[token];
        if(address(strategy) != address(0)){
           int256 tokenPriceInETH = oracle.getLatestPrice(address(token));
           uint256 tokenAmountInETH = uint256(tokenPriceInETH) * amount / 1e18;
           shares = _convertToShares(tokenAmountInETH, Math.Rounding.Floor);
        }
    }
}
