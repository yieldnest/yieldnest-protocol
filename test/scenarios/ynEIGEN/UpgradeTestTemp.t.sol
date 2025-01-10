// // SPDX-License-Identifier: BSD 3-Clause License
// pragma solidity ^0.8.24;

// import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// import "forge-std/Test.sol";
// import "script/Utils.sol";

// contract SmallTest is Test, Utils {

//     // address _proxy = 0x58c721D3f6FcdE97ef07df793D359DbCc1fDB36d;
//     // address _newImplementation = 0xD82d61C2905595f554233De5cDb947979802267C;

//     // holesky
//     address _proxy = 0xA1C5E681D143377F78eF727db73Deaa70EE4441f; // withdrawlsProcessorProxy
//     address _newImplementation = 0xdDb2282f56A7355DD904E7d1074980d69A6bAFd3; // withdrawalsProcessorV2
//     address _ynSecurityCouncil = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
//     address keeper = 0xbc345A8aEd2ff40308Cf923216dF39B5bE1146b2; // YNnWithdrawalsYnEigen
//     address proxyAdmin = 0xB1D96f8fb245194B6Ef025F1a0697964b719186C;
//     TimelockController timelockController = TimelockController(payable(0x62173555C27C67644C5634e114e42A63A59CD7A5));

//     function setUp() public {
//         vm.selectFork(vm.createFork(vm.envString("HOLESKY_RPC_URL")));
//     }

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
//         console.log("timelockController: ", address(timelockController));
//         console.log("proxyAdmin: ", proxyAdmin);
//         console.log("ynSecurityCouncil: ", _ynSecurityCouncil);

//         vm.startPrank(_ynSecurityCouncil);
//         timelockController.schedule(
//             // getTransparentUpgradeableProxyAdminAddress(_proxyAddress), // target
//             proxyAdmin, // proxyadmin
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
//             proxyAdmin, // target
//             0, // value
//             _data,
//             bytes32(0), // predecessor
//             bytes32(0) // salt
//         );
//         vm.stopPrank();
//     }
// }
// //target-- 0xB1D96f8fb245194B6Ef025F1a0697964b719186C
// //data-- 0x9623609d000000000000000000000000a1c5e681d143377f78ef727db73deaa70ee4441f000000000000000000000000ddb2282f56a7355dd904e7d1074980d69a6bafd300000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000