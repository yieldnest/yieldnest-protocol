pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./YieldNestOracle.sol";


interface yLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);
}

contract yLSD is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, yLSDEvents {
    using SafeERC20 for IERC20;

    error UnsupportedToken(IERC20 token);
    error ZeroAmount();

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    YieldNestOracle oracle;
    IStrategyManager public strategyManager;

    mapping(IERC20 => IStrategy) public strategies;
    mapping(address => uint) public depositedBalances;
    mapping(address => uint) public totalTokenShares;
    mapping(address => mapping(address => uint)) public userShares;

    IERC20[] tokens;

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

        if(token.allowance(address(this), address(strategyManager)) < amount) {
            token.approve(address(strategyManager), amount);
        }

        strategyManager.depositIntoStrategy(
                strategy,
                token,
                amount
            );

        depositedBalances[address(token)] += amount;
        shares = _convertToShares(amount, Math.Rounding.Floor);

        userShares[address(token)][msg.sender] += shares;
        totalTokenShares[address(token)] += shares;
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

    // TODO Refactor this part better
    // totalSupply() should be calculated differently 
    function _convertToShares(address token, uint amount,  Math.Rounding rounding) internal view returns (uint256) {
        // 1:1 exchange rate on the first stake.
        // Use totalSupply to see if this is the boostrap call, not totalAssets
        if (totalSupply() == 0) {
            return amount;
        }
        
        // Can only happen in bootstrap phase if `totalControlled` and `ynETHSupply` could be manipulated
        // independently. That should not be possible.
        return Math.mulDiv(
            amount,
            totalTokenShares[token] * uint256(_BASIS_POINTS_DENOMINATOR - exchangeAdjustmentRate),
            depositedBalances[token] * uint256(_BASIS_POINTS_DENOMINATOR),
            rounding
        );
    }


    function totalAssets() public view returns (uint) {
        uint total = 0;
        for (uint i = 0; i < tokens.length; i++) {
            int256 price = oracle.getLatestPrice(address(tokens[i]));
            uint256 balance = depositedBalances[tokens[i]];
            total += uint256(price) * balance / 1e18;
        }
        return total;
    }

}
