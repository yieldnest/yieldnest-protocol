// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

library Invariants {
  
	/**
	* @dev Compares two uint256 values and checks if their difference is within a specified threshold.
	* @param value1 The first uint256 value.
	* @param value2 The second uint256 value.
	* @param threshold The threshold for the difference between value1 and value2.
	* @return bool Returns true if the difference between value1 and value2 is less than or equal to the threshold.
	*/
	function compareWithThreshold(uint256 value1, uint256 value2, uint256 threshold) public pure returns (bool) {
		if(value1 > value2) {
			return (value1 - value2) <= threshold;
		} else {
			return (value2 - value1) <= threshold;
		}
	}

	/// Share and Assets Invariants
	function shareMintIntegrity (uint256 totalSupply, uint256 previousTotal, uint256 newShares) public pure {
		require(compareWithThreshold(totalSupply, previousTotal + newShares, 2) == true,
			"Invariant: Total supply should be equal to previous total plus new shares"
		);
	}

	function totalDepositIntegrity (uint256 totalDeposited, uint256 previousTotal, uint256 newDeposited) public pure {
		require(compareWithThreshold(totalDeposited, previousTotal + newDeposited, 2) == true,
			"Invariant: Total deposited should be equal to previous total plus new deposited"
		);
	}

	function userSharesIntegrity (uint256 userShares, uint256 previousShares, uint256 newShares) public pure {
		require(compareWithThreshold(userShares, previousShares + newShares, 2) == true,
			"Invariant: User shares should be equal to previous shares plus new shares"
		);
	}

	function totalAssetsIntegrity (uint256 totalAssets, uint256 previousAssets, uint256 newAssets) public pure {
		require(compareWithThreshold(totalAssets, previousAssets + newAssets, 2) == true,
			"Invariant: Total assets should be equal to previous assets plus new assets"
		);
	}

	function totalBalanceIntegrity (uint256 balance, uint256 previousBalance, uint256 newBalance) public pure {
		require(compareWithThreshold(balance, previousBalance + newBalance, 2) == true,
			"Invariant: Total balance should be equal to previous balance plus new balance"
		);
	}
}