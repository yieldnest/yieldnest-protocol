pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./YieldNestOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IynLSD.sol";

contract ynLSD is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IynLSDEvents {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");


    error UnsupportedToken(IERC20 token);
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch(uint256 firstLength, uint256 secondLength);

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    YieldNestOracle public oracle;
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


    function initialize(Init memory init) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(ADMIN_ROLE, msg.sender);

        for (uint i = 0; i < init.tokens.length; i++) {
            tokens.push(init.tokens[i]);
            strategies[init.tokens[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        oracle = init.oracle;
        exchangeAdjustmentRate = init.exchangeAdjustmentRate;
    }

    // ==================================== VIEW FUNCTIONS =========================================
    /**
     * @notice This function calculates the total assets of the contract
     * @dev It iterates over all the tokens in the contract, gets the latest price for each token from the oracle, 
     * multiplies it with the balance of the token and adds it to the total
     * @return total The total assets of the contract in the form of uint
     */
    function totalAssets() public view returns (uint total) {
        for (uint i = 0; i < tokens.length; i++) {
            int256 price = oracle.getLatestPrice(address(tokens[i]));
            uint256 balance = depositedBalances[tokens[i]];
            total += uint256(price) * balance / 1e18;
        }
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

    // ==================================== EXTERNAL FUNCTIONS =========================================


    /// @notice Deposit tokens to obtain shares (eliminates script injection)
    /// @param token the ERC-20 token that is deposited
    /// @param amount amount of ERC-20 tokens deposited
    /// @return shares the amount of shares received
    function deposit(
        IERC20 token,
        uint256 amount
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        shares = _deposit(
                    token,
                    amount,
                    msg.sender
                );
    }

    // ==================================== INTERNAL FUNCTIONS =========================================

    /**
     * @notice Deposits a token amount into a strategy, returning equivalent shares
     * @dev 
     * - Checks if the amount is non-zero and if the token's strategy exists. 
     * - Transfers tokens from sender to this contract and approves strategyManager to spend them. 
     * - Calls depositIntoStrategy function of strategyManager to deposit tokens into the strategy and get equivalent shares. 
     * - Adds the amount to the token's depositedBalances, converts the token amount to ETH. 
     * - Calculates the shares to be minted using _convertToShares function and mints the shares to the receiver. 
     * - Emits a Deposit event.
     * @param token The ERC-20 token to deposit
     * @param amount The token amount to deposit
     * @param receiver The address to receive the shares
     * @return shares The shares minted to the receiver
     */
    function _deposit(
        IERC20 token,
        uint256 amount,
        address receiver
    ) internal returns (uint256 shares) {

        if (amount == 0) {
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

    // ==================================== CONTRACT MANAGEMENT =========================================

    function setStrategyManager(address _strategyManager) external onlyRole(ADMIN_ROLE) {
        if(_strategyManager == address(0)) revert ZeroAddress();
        strategyManager = IStrategyManager(_strategyManager);
    }

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if(_oracle == address(0)) revert ZeroAddress();
        oracle = YieldNestOracle(_oracle);
    }

    function setStrategies(IERC20[] memory _tokens, address[] memory _strategies) external onlyRole(ADMIN_ROLE) {
        if(_tokens.length != _strategies.length) revert LengthMismatch(_tokens.length, _strategies.length);
        for (uint i = 0; i < _tokens.length; i++) {
            if(address(_tokens[i]) == address(0) || _strategies[i] == address(0)) revert ZeroAddress();
            strategies[_tokens[i]] = IStrategy(_strategies[i]);
        }
    }

}
