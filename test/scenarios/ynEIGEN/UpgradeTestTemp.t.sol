// // SPDX-License-Identifier: BSD 3-Clause License
// pragma solidity ^0.8.24;

// import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// import "forge-std/Test.sol";

// contract SmallTest is Test {

//     address _proxy = 0x58c721D3f6FcdE97ef07df793D359DbCc1fDB36d;
//     address _newImplementation = 0xD82d61C2905595f554233De5cDb947979802267C;
//     address _ynSecurityCouncil = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
//     TimelockController timelockController = TimelockController(payable(0x317f96879FA387aFF6dfFAAc4A09bD2f6e367801));

//     function setUp() public {}

//     function testSmall() public {
//         bytes memory _data = abi.encodeWithSignature(
//             "upgradeAndCall(address,address,bytes)",
//             _proxy, // proxy
//             _newImplementation, // implementation
//             ""
//         );
//         console.logBytes(_data);
//         console.log("15 minutes: ", 15 minutes);
//         console.logBytes32(bytes32(0));
//         vm.startPrank(_ynSecurityCouncil);
//         timelockController.schedule(
//             // getTransparentUpgradeableProxyAdminAddress(_proxyAddress), // target
//             0x3BE30C73AF6b1c5d6d13E20B41D89a81FC074211,
//             0, // value
//             _data,
//             bytes32(0), // predecessor
//             bytes32(0), // salt
//             timelockController.getMinDelay() // delay
//         );
//         vm.stopPrank();

//         uint256 minDelay;
//         if (block.chainid == 1) { // Mainnet
//             minDelay = 3 days;
//         } else if (block.chainid == 17000) { // Holesky
//             minDelay = 15 minutes;
//         } else {
//             revert("Unsupported chain ID");
//         }
//         skip(minDelay);

//         vm.startPrank(_ynSecurityCouncil);
//         timelockController.execute(
//             0x3BE30C73AF6b1c5d6d13E20B41D89a81FC074211, // target
//             0, // value
//             _data,
//             bytes32(0), // predecessor
//             bytes32(0) // salt
//         );
//         vm.stopPrank();
//     }
// }