pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./YieldNestOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface yLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
}

contract yLSD is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, yLSDEvents {
    using SafeERC20 for IERC20;

    error UnsupportedToken(IERC20 token);
    error ZeroAmount();
    error LowAmountOfShares(uint sharesProvided, uint sharesExpected);

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    YieldNestOracle oracle;
    IStrategyManager public strategyManager;

    mapping(IERC20 => IStrategy) public strategies;
    mapping(IERC20 => uint) public depositedBalances;

    IERC20[] tokens;

    uint exchangeAdjustmentRate;

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

    // ==================================== VIEW FUNCTIONS =========================================

    function totalAssets() public view returns (uint total) {
        for (uint i = 0; i < tokens.length; i++) {
            int256 price = oracle.getLatestPrice(address(tokens[i]));
            uint256 balance = depositedBalances[tokens[i]];
            total += uint256(price) * balance / 1e18;
        }
    }

    function getSharesForToken(IERC20 token, uint amount) external view returns(uint shares) {
        IStrategy strategy = strategies[token];
        if(address(strategy) != address(0)){
           int256 tokenPriceInETH = oracle.getLatestPrice(address(token));
           uint256 tokenAmountInETH = uint256(tokenPriceInETH) * amount / 1e18;
           shares = _convertToShares(tokenAmountInETH, Math.Rounding.Floor);
        }
    }

    // ==================================== EXTERNAL FUNCTIONS =========================================


    /// @notice Deposit tokens to obtain shares (eliminates script injection)
    /// @param token the ERC-20 token that is deposited
    /// @param amount amount of ERC-20 tokens deposited
    /// @param minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function deposit(
        IERC20 token,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
         _deposit(
            token,
            msg.sender,
            amount,
            minExpectedAmountOfShares
        );
    }

    /// @notice Deposit tokens to obtain shares on behalf of receiver
    /// @param token the ERC-20 token that is deposited
    /// @param receiver the address that receives the shares
    /// @param amount amount of ERC-20 tokens deposited
    /// @param minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function depositOnBehalf(
        IERC20 token,
        address receiver,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
         _deposit(
            token,
            receiver,
            amount,
            minExpectedAmountOfShares
        );
    }

    // ==================================== INTERNAL FUNCTIONS =========================================


    function _deposit(
        IERC20 token,
        address receiver,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) internal returns (uint256 shares) {

        if (amount == 0 || minExpectedAmountOfShares == 0) {
            revert ZeroAmount();
        }

        IStrategy strategy = strategies[token];
        if(address(strategy) == address(0x0)){
            revert UnsupportedToken(token);
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        if(token.allowance(address(this), address(strategyManager)) < amount) {
            token.approve(address(strategyManager), amount);
        }

        strategyManager.depositIntoStrategy(
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

        if(shares < minExpectedAmountOfShares) {
            revert LowAmountOfShares(shares, minExpectedAmountOfShares);
        }

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


}
