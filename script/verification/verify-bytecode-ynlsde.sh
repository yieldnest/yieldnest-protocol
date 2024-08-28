#!/bin/bash

# Read the deployment JSON file
DEPLOYMENT_FILE="./deployments/YnLSDe-1.json"

# List of contracts to verify
contracts=("YnLSDe" "assetRegistry" "eigenStrategyManager" "tokenStakingNodesManager" "ynEigenDepositAdapter" "rateProvider")

# Note: verify "ynEigenViewer" manually. more difficult to craft parameter bytecode verification

# Read the Etherscan API key from .env file
ETHERSCAN_API_KEY=$(grep ETHERSCAN_API_KEY .env | cut -d '=' -f2 | tr -d '[:space:]')

# Log ETHERSCAN_API_KEY (masked for security)
echo "ETHERSCAN_API_KEY: ${ETHERSCAN_API_KEY:0:4}...${ETHERSCAN_API_KEY: -4}"


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
    elif [ "$contract_key" == "upgradeTimelock" ]; then
        solidity_contract="TimelockController"
    elif [ "$contract_key" == "tokenStakingNodeImplementation" ]; then
        solidity_contract="TokenStakingNode"
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

verify_implementation() {
    local impl_address=$1
    local solidity_contract=$2
    local contract_name=$3

    # Get bytecode from Etherscan
    local etherscan_sha256=$(curl -X GET "https://api.etherscan.io/api?module=proxy&action=eth_getCode&address=$impl_address&tag=latest&apikey=$ETHERSCAN_API_KEY" | jq -r '.result' | sha256sum)

    # Get local bytecode
    local local_sha256=$(cat "out/$solidity_contract.sol/$solidity_contract.json" | jq -r '.deployedBytecode.object' | sed 's/"//g' | sha256sum)

    # Compare SHA256 hashes
    if [ "$etherscan_sha256" = "$local_sha256" ]; then
        echo  "✅ Bytecode verification successful for $contract_name"
    else
        echo -e "❌ Error: Bytecode mismatch for $contract_name"
        echo -e "❌ Etherscan SHA256: $etherscan_sha256"
        echo -e "❌ Local SHA256: $local_sha256"
        return 1
    fi
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

    verify_implementation "$impl_address" "$solidity_contract" "$contract_name"
}

# Extract upgradeTimelock address
upgradeTimelock=$(jq -r '.upgradeTimelock' "$DEPLOYMENT_FILE")

verify_contract "" $upgradeTimelock "" "upgradeTimelock"

# Extract tokenStakingNodeImplementation address
tokenStakingNodeImplementation=$(jq -r '.tokenStakingNodeImplementation' "$DEPLOYMENT_FILE")

verify_contract "" $tokenStakingNodeImplementation "" "tokenStakingNodeImplementation"



for contract in "${contracts[@]}"; do
    read proxy impl proxy_admin <<< $(extract_addresses $contract)

    echo "Extracted addresses for $contract:"
    echo "  Proxy: $proxy"
    echo "  Implementation: $impl"
    echo "  Proxy Admin: $proxy_admin"
    echo ""
    verify_contract $proxy $impl $proxy_admin $contract
done