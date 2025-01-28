// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayLib {
    /**
     * @notice Deduplicates an array of addresses by removing duplicates while preserving order
     * @param arr The input array of addresses to deduplicate
     * @return result The deduplicated array of addresses
     */
    function deduplicate(address[] memory arr) internal pure returns (address[] memory result) {
        if (arr.length == 0) {
            return new address[](0);
        }

        // First pass: count unique elements
        uint256 uniqueCount = 1;
        for (uint256 i = 1; i < arr.length; i++) {
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (arr[i] == arr[j]) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate) {
                uniqueCount++;
            }
        }

        // Second pass: populate result array
        result = new address[](uniqueCount);
        result[0] = arr[0];
        uint256 resultIndex = 1;
        
        for (uint256 i = 1; i < arr.length; i++) {
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (arr[i] == arr[j]) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate) {
                result[resultIndex] = arr[i];
                resultIndex++;
            }
        }

        return result;
    }
}
