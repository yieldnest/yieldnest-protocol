// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

library Invariants {

  /// Share and Assets Invariants
  function shareMintIntegrity (uint256 totalSupply, uint256 previousTotal, uint256 newShares) public pure {
    require(totalSupply == previousTotal + newShares,
      "Invariant: Total supply should be equal to previous total plus new shares"
    );
  }

  function totalDepositIntegrity (uint256 totalDeposited, uint256 previousTotal, uint256 newDeposited) public pure {
    require(totalDeposited == previousTotal + newDeposited,
      "Invariant: Total deposited should be equal to previous total plus new deposited"
    );
  }

  function userSharesIntegrity (uint256 userShares, uint256 previousShares, uint256 newShares) public pure {
    require(userShares == previousShares + newShares,
      "Invariant: User shares should be equal to previous shares plus new shares"
    );
  }

  function totalAssetsIntegrity (uint256 totalAssets, uint256 previousAssets, uint256 newAssets) public pure {
    require(totalAssets == previousAssets + newAssets,
      "Invariant: Total assets should be equal to previous assets plus new assets"
    );
  }

  function totalBalanceIntegrity (uint256 balance, uint256 previousBalance, uint256 newBalance) public pure {
    require(balance == previousBalance + newBalance,
      "Invariant: Total balance should be equal to previous balance plus new balance"
    );
  }
}