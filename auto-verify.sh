#!/bin/bash

# Change these values as needed
chain=$CHAIN # e.g. mainnet, holesky
rpc=$RPC_URL
api_key=$ETHERSCAN_API_KEY
json_file="broadcast/DeployYieldNest.s.sol/17000/run-latest.json"

# Extract contract names and addresses to an intermediate file for processing
jq -r '.transactions[] | "\(.contractName) \(.contractAddress)"' $json_file > contracts_to_verify.txt

# Read each line from the intermediate file
while IFS= read -r line; do
    # Split the line into name and address
    read -ra ADDR <<< "$line"
    contract_name="${ADDR[0]}"
    contract_address="${ADDR[1]}"

    # Skip if contract_name or contract_address is empty
    if [ -z "$contract_name" ] || [ -z "$contract_address" ]; then
        continue
    fi

    echo "Verifying $contract_name at $contract_address"

    path=src/$contract_name.sol:$contract_name

    # if the contract name is TransparentUpgradeableProxy, we need to verify the implementation contract
    if [ "$contract_name" == "TransparentUpgradeableProxy" ]; then
        # Get the implementation address
        path=lib/openzeppelin-contracts/contracts/proxy/transparent/$contract_name.sol:$contract_name
    fi

    echo "Path: $path"
    # Add your forge verify-contract command below, customize it as needed
    forge verify-contract --guess-constructor-args --compiler-version v0.8.24+commit.e11b9ed9 --num-of-optimizations 200 --chain-id $chain $contract_address $path --rpc-url $rpc --api-key $api_key --watch
    # Note: You'll need to replace placeholders with actual values suitable for your contracts

done < contracts_to_verify.txt

# Cleanup intermediate file
rm contracts_to_verify.txt