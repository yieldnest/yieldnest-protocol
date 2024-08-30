// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";


interface CoinbaseToken {
    function exchangeRate() external view returns (uint256);
}

struct StaderExchangeRate {
    uint256 block_number;
    uint256 eth_balance;
    uint256 ethx_supply;
}

interface StaderOracle {
    function getExchangeRate() external view returns (StaderExchangeRate memory);
}



contract PrintRolesKeccak is Script {
    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        // Define the address of the Coinbase token contract
        // address CB_ASSET_ADDRESS = chainAddresses.lsd.CBETH_ADDRESS;

        // // Create an instance of the CoinbaseToken interface
        // CoinbaseToken cbToken = CoinbaseToken(CB_ASSET_ADDRESS);

        // // Print the Coinbase token address
        // console.log("Coinbase Token Address:", CB_ASSET_ADDRESS);

        // // Read the exchange rate
        // uint256 exchangeRate = cbToken.exchangeRate();

        // // Print the exchange rate
        // console.log("Coinbase Token Exchange Rate:", exchangeRate);

        // Define ETHX_ADDRESS based on the current chain
        address ETHX_ADDRESS;
        if (block.chainid == 1) { // Mainnet
            ETHX_ADDRESS = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
        } else if (block.chainid == 17000) { // Holesky
            ETHX_ADDRESS = 0xB4F5fc289a778B80392b86fa70A7111E5bE0F859;
        } else {
            revert("Unsupported chain");
        }

        console.log("ETHX_ADDRESS:", ETHX_ADDRESS);

        // Define STADER_ORACLE address based on the current chain
        address STADER_ORACLE;
        if (block.chainid == 1) { // Mainnet
            STADER_ORACLE = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
        } else if (block.chainid == 17000) { // Holesky
            STADER_ORACLE = 0x90ED1c6563e99Ea284F7940b1b443CE0BC4fC3e4; // Replace with actual Holesky address if available
        } else {
            revert("Unsupported chain");
        }

        console.log("STADER_ORACLE:", STADER_ORACLE);

        // Create an instance of the StaderOracle interface
        StaderOracle staderOracle = StaderOracle(STADER_ORACLE);

        // Read the exchange rate
        StaderExchangeRate memory res = staderOracle.getExchangeRate();

        // Calculate the rate
        uint256 UNIT = 1e18; // Assuming 18 decimal places
        uint256 rate = (res.eth_balance * UNIT) / res.ethx_supply;

        // Print the exchange rate
        console.log("ETHX Exchange Rate:", rate);

        bytes32 PROXY_ADMIN_OWNER = keccak256("PROXY_ADMIN_OWNER_ROLE");
        bytes32 DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
        bytes32 STAKING_ADMIN = keccak256("STAKING_ADMIN_ROLE");

        bytes32 STAKING_NODES_DELEGATOR = keccak256("STAKING_NODES_DELEGATOR_ROLE");
        bytes32 REWARDS_ADMIN = keccak256("REWARDS_ADMIN_ROLE");
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");
        bytes32 UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
        bytes32 FEE_RECEIVER = keccak256("FEE_RECEIVER_ROLE");
        bytes32 VALIDATOR_MANAGER = keccak256("VALIDATOR_MANAGER_ROLE");
        bytes32 STAKING_NODES_OPERATOR = keccak256("STAKING_NODES_OPERATOR_ROLE");
        bytes32 STAKING_NODE_CREATOR = keccak256("STAKING_NODE_CREATOR_ROLE");
        bytes32 POOLED_DEPOSITS_OWNER = keccak256("POOLED_DEPOSITS_OWNER_ROLE");

        console.log("PROXY_ADMIN_OWNER: ", vm.toString(PROXY_ADMIN_OWNER));
        console.log("DEFAULT_ADMIN_ROLE: ", vm.toString(DEFAULT_ADMIN_ROLE));
        console.log("STAKING_ADMIN: ", vm.toString(STAKING_ADMIN));
        console.log("STAKING_NODES_DELEGATOR: ", vm.toString(STAKING_NODES_DELEGATOR));
        console.log("REWARDS_ADMIN: ", vm.toString(REWARDS_ADMIN));
        console.log("PAUSER_ROLE: ", vm.toString(PAUSER_ROLE));
        console.log("UNPAUSER_ROLE: ", vm.toString(UNPAUSER_ROLE));
        console.log("FEE_RECEIVER: ", vm.toString(FEE_RECEIVER));
        console.log("VALIDATOR_MANAGER: ", vm.toString(VALIDATOR_MANAGER));
        console.log("STAKING_NODES_OPERATOR: ", vm.toString(STAKING_NODES_OPERATOR));
        console.log("STAKING_NODE_CREATOR: ", vm.toString(STAKING_NODE_CREATOR));
        console.log("POOLED_DEPOSITS_OWNER: ", vm.toString(POOLED_DEPOSITS_OWNER));

    }
}
