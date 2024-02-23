pragma solidity ^0.8.0;

import "../interfaces/eigenlayer-init-mainnet/IStrategy.sol";

contract MockStrategy is IStrategy {
    constructor() {}

    uint public multiplier;
    address public token;
    
    function setMultiplier(uint _multiplier) external {
        multiplier = _multiplier;
    }
    
    function setToken(address _token) external {
        token = _token;
    }

    function deposit(IERC20 token, uint256 amount) external virtual override returns (uint256){
        return amount*multiplier;
    }

    function totalShares() external view virtual override returns (uint256) {
        return 18;
    }

    function withdraw(address depositor, IERC20 token, uint256 amountShares) external virtual override {  

    }

    function sharesToUnderlying(uint256 amountShares) external view virtual override returns (uint256) {  
        return amountShares*multiplier;
    }
   
    function underlyingToShares(uint256 amountUnderlying) external view virtual override returns (uint256) {  
        return amountUnderlying*multiplier;
    }

    function userUnderlying(address user) external view virtual override returns (uint256) {  
        return 10*multiplier;
    }

    function sharesToUnderlyingView(uint256 amountShares) external view virtual override returns (uint256)  {  
        return amountShares*multiplier;
    }

    function underlyingToSharesView(uint256 amountUnderlying) external view virtual override returns (uint256)  {  
        return amountUnderlying*multiplier;
    }
    function userUnderlyingView(address user) external view virtual override returns (uint256)  {  
        return 10*multiplier;
    }

    function underlyingToken() external view virtual override returns (IERC20) {
        return IERC20(token);
    }

    function explanation() external view virtual override returns (string memory) {
        return "1";
    }

}

