pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./YieldNestOracle.sol";


interface ynLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
}

contract ynLSD is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ynLSDEvents {
    using SafeERC20 for IERC20;

    error UnsupportedToken(IERC20 token);
    error ZeroAmount();
    error LowAmountOfShares(uint sharesProvided, uint sharesExpected);

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    YieldNestOracle oracle;
    IStrategyManager public strategyManager;

    mapping(IERC20 => IStrategy) public strategies;
    mapping(IERC20 => uint) public depositedBalances;
    mapping(IERC20 => uint) public currentPrice;

    IERC20[] tokens;

    uint public exchangeAdjustmentRate;
    uint public latestAssetUpdate;
    uint public totalAssets;

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

    /// @notice Update the assets state and deposit tokens to obtain shares
    /// @param _token the ERC-20 token that is deposited
    /// @param _amount amount of ERC-20 tokens deposited
    /// @param _minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function updateAndDeposit(
        IERC20 token,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        if(latestAssetUpdate + 1 minutes <= block.timestamp) {
            _updateTotalAssets();
        }
        _depost(
            token,
            msg.sender,
            amount,
            minExpectedAmountOfShares
        );
    }

    /// @notice Deposit tokens to obtain shares
    /// @param _token the ERC-20 token that is deposited
    /// @param _amount amount of ERC-20 tokens deposited
    /// @param _minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function deposit(
        IERC20 token,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
         _depost(
            token,
            msg.sender,
            amount,
            minExpectedAmountOfShares
        );
    }

    /// @notice Update the assets state and deposit tokens to obtain shares on behalf of receiver
    /// @param _token the ERC-20 token that is deposited
    /// @param _receiver the address that receives the shares
    /// @param _amount amount of ERC-20 tokens deposited
    /// @param _minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function updateAndDepositOnBehalf(
        IERC20 token,
        address receiver,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        if(latestAssetUpdate + 1 minutes <= block.timestamp) {
            _updateTotalAssets();
        }
        _depost(
            token,
            receiver,
            amount,
            minExpectedAmountOfShares
        );

    }

    /// @notice Deposit tokens to obtain shares on behalf of receiver
    /// @param _token the ERC-20 token that is deposited
    /// @param _receiver the address that receives the shares
    /// @param _amount amount of ERC-20 tokens deposited
    /// @param _minExpectedAmountOfShares the minimum amount of expected shares the receiver should receive
    /// @return shares the amount of shares received
    function depositOnBehalf(
        IERC20 token,
        address receiver,
        uint256 amount,
        uint256 minExpectedAmountOfShares
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
         _depost(
            token,
            receiver,
            amount,
            minExpectedAmountOfShares
        );
    }
    
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

        // Calculate how many shares to be minted using the same formula as ynETH
        shares = _convertToShares(token, amount, Math.Rounding.Floor);

        if(shares < minExpectedAmountOfShares) {
            revert LowAmountOfShares(shares, minExpectedAmountOfShares);
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

        // Mint the calculated shares to the receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares);
    }

    function totalSupply() public view returns(uint256) {
        uint totalSupply_;
        for(uint i=0; i<tokens.length, i++) {
            totalSupply_ += totalTokenShares[address(tokens[i])];
        }
        return totalSupply_;
    }

    function _convertToShares(IERC20 token, uint256 amount, Math.Rounding rounding) internal view returns (uint256) {

        uint ethAmount = amount * currentPrice[token];
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) {
            return amount;
        }

        return Math.mulDiv(
            ethAmount,
            totalSupply() * uint256(_BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            totalAssets * uint256(_BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }


}
