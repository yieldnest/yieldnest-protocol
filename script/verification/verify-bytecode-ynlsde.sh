#!/bin/bash

# Read the deployment JSON file
DEPLOYMENT_FILE="./deployments/YnLSDe-1.json"

# List of contracts to verify
contracts=("YnLSDe" "assetRegistry" "eigenStrategyManager" "tokenStakingNodesManager" "ynEigenDepositAdapter" "rateProvider" "ynEigenViewer")


get_solidity_contract_name() {
    local contract_key=$1
    local solidity_contract=""

    if [ "$contract_key" == "YnLSDe" ]; then
        solidity_contract="ynEigen"
    elif [ "$contract_key" == "assetRegistry" ]; then
        solidity_contract="AssetRegistry"
    elif [ "$contract_key" == "eigenStrategyManager" ]; then
        solidity_contract="EigenStrategyManager"
    elif [ "$contract_key" == "tokenStakingNodesManager" ]; then
        solidity_contract="TokenStakingNodesManager"
    elif [ "$contract_key" == "ynEigenDepositAdapter" ]; then
        solidity_contract="ynEigenDepositAdapter"
    elif [ "$contract_key" == "rateProvider" ]; then
        solidity_contract="LSDRateProvider"
    elif [ "$contract_key" == "ynEigenViewer" ]; then
        solidity_contract="ynEigenViewer"
    else
        echo "Error: Unknown contract key '$contract_key'" >&2
        return 1
    fi

    echo "$solidity_contract"
}

# Function to extract proxy and implementation addresses
extract_addresses() {
    local key=$1
    local proxy_address=$(jq -r ".[\"proxy-$key\"]" "$DEPLOYMENT_FILE")
    local impl_address=$(jq -r ".[\"implementation-$key\"]" "$DEPLOYMENT_FILE")
    local proxy_admin=$(jq -r ".[\"proxyAdmin-$key\"]" "$DEPLOYMENT_FILE")
    echo "$proxy_address $impl_address $proxy_admin"
}

# Function to verify a contract
verify_contract() {
    local proxy_address=$1
    local impl_address=$2
    local proxy_admin=$3
    local contract_name=$4

    # Get the Solidity contract name
    local solidity_contract=$(get_solidity_contract_name "$contract_name")
    if [ -z "$solidity_contract" ]; then
        echo "Error: No Solidity contract name found for $contract_name"
        return 1
    fi

    echo "Verifying $contract_name (Solidity contract: $solidity_contract)..."

    # Get bytecode from Etherscan
    local etherscan_bytecode=$(curl -s -X GET "https://api.etherscan.io/api?module=proxy&action=eth_getCode&address=$impl_address&tag=latest&apikey=$ETHERSCAN_API_KEY" | jq -r '.result')
    
    # Calculate SHA256 of Etherscan bytecode
    local etherscan_sha256=$(echo -n "$etherscan_bytecode" | sed 's/0x//' | xxd -r -p | sha256sum | awk '{print $1}')

    # Get local bytecode
    local local_bytecode=$(cat "out/$solidity_contract.sol/$solidity_contract.json" | jq -r '.deployedBytecode.object')
    
    # Calculate SHA256 of local bytecode
    local local_sha256=$(echo -n "$local_bytecode" | xxd -r -p | sha256sum | awk '{print $1}')

    # Compare SHA256 hashes
    if [ "$etherscan_sha256" = "$local_sha256" ]; then
        echo "Bytecode verification successful for $contract_name"
    else
        echo "Error: Bytecode mismatch for $contract_name"
        echo "Etherscan SHA256: $etherscan_sha256"
        echo "Local SHA256: $local_sha256"
        return 1
    fi
}

for contract in "${contracts[@]}"; do
    read proxy impl proxy_admin <<< $(extract_addresses $contract)

    echo "Extracted addresses for $contract:"
    echo "  Proxy: $proxy"
    echo "  Implementation: $impl"
    echo "  Proxy Admin: $proxy_admin"
    echo ""
    verify_contract $proxy $impl $proxy_admin $contract
done