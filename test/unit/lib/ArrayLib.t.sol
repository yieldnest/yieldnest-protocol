// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ArrayLib} from "../../../src/lib/ArrayLib.sol";

contract ArrayLibTest is Test {
    function testDeduplicateEmptyArray() public {
        address[] memory arr = new address[](0);
        address[] memory result = ArrayLib.deduplicate(arr);
        assertEq(result.length, 0, "Empty array should return empty array");
    }

    function testDeduplicateSingleElement() public {
        address[] memory arr = new address[](1);
        arr[0] = address(0x1);
        
        address[] memory result = ArrayLib.deduplicate(arr);
        
        assertEq(result.length, 1, "Single element array should return single element");
        assertEq(result[0], address(0x1), "Element should match input");
    }

    function testDeduplicateNoDuplicates() public {
        address[] memory arr = new address[](3);
        arr[0] = address(0x1);
        arr[1] = address(0x2); 
        arr[2] = address(0x3);

        address[] memory result = ArrayLib.deduplicate(arr);

        assertEq(result.length, 3, "Array with no duplicates should maintain length");
        assertEq(result[0], address(0x1), "First element should match");
        assertEq(result[1], address(0x2), "Second element should match");
        assertEq(result[2], address(0x3), "Third element should match");
    }

    function testDeduplicateWithDuplicates() public {
        address[] memory arr = new address[](5);
        arr[0] = address(0x1);
        arr[1] = address(0x2);
        arr[2] = address(0x1); // Duplicate
        arr[3] = address(0x3);
        arr[4] = address(0x2); // Duplicate

        address[] memory result = ArrayLib.deduplicate(arr);

        assertEq(result.length, 3, "Duplicates should be removed");
        assertEq(result[0], address(0x1), "First unique element should match");
        assertEq(result[1], address(0x2), "Second unique element should match");
        assertEq(result[2], address(0x3), "Third unique element should match");
    }

    function testDeduplicateAllSameElements() public {
        address[] memory arr = new address[](3);
        arr[0] = address(0x1);
        arr[1] = address(0x1);
        arr[2] = address(0x1);

        address[] memory result = ArrayLib.deduplicate(arr);

        assertEq(result.length, 1, "Array with all same elements should return single element");
        assertEq(result[0], address(0x1), "Element should match input");
    }

    function testDeduplicatePreservesOrder() public {
        address[] memory arr = new address[](6);
        arr[0] = address(0x1);
        arr[1] = address(0x2);
        arr[2] = address(0x3);
        arr[3] = address(0x2); // Duplicate
        arr[4] = address(0x4);
        arr[5] = address(0x1); // Duplicate

        address[] memory result = ArrayLib.deduplicate(arr);

        assertEq(result.length, 4, "Should have 4 unique elements");
        assertEq(result[0], address(0x1), "First element should be first occurrence of 0x1");
        assertEq(result[1], address(0x2), "Second element should be first occurrence of 0x2");
        assertEq(result[2], address(0x3), "Third element should be 0x3");
        assertEq(result[3], address(0x4), "Fourth element should be 0x4");
    }
}
