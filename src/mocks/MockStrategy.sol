pragma solidity ^0.8.0;

import "../interfaces/eigenlayer-init-mainnet/IStrategy.sol";

contract MockStrategy is IStrategy {
    constructor() {}

    function deposit(IERC20 token, uint256 amount) external virtual override returns (uint256){
        
    }

    function totalShares() external view virtual override returns (uint256) {
        return 18;
    }

    function withdraw(address depositor, IERC20 token, uint256 amountShares) external virtual override {  

    }

    function sharesToUnderlying(uint256 amountShares) external view virtual override returns (uint256) {  

    }
   
    function underlyingToShares(uint256 amountUnderlying) external view virtual override returns (uint256) {  
        return 1;
    }

    function userUnderlying(address user) external view virtual override returns (uint256) {  
        return 1;
    }

    function sharesToUnderlyingView(uint256 amountShares) external view virtual override returns (uint256)  {  
        return 1;
    }

    function underlyingToSharesView(uint256 amountUnderlying) external view virtual override returns (uint256)  {  
        return 1;
    }
    function userUnderlyingView(address user) external view virtual override returns (uint256)  {  
        return 1;
    }

    function underlyingToken() external view virtual override returns (IERC20) {
        return IERC20(address(1));
    }

    function explanation() external view virtual override returns (string memory) {
        return "1";
    }

}

