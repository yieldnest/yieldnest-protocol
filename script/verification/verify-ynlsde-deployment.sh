#!/bin/bash

# Read the deployment JSON file
DEPLOYMENT_FILE="./deployments/YnLSDe-17000.json"
# Read the Etherscan API key from .env file
ETHERSCAN_API_KEY=$(grep ETHERSCAN_API_KEY .env | cut -d '=' -f2)
# Read the RPC URL from .env file
RPC_URL=$(grep RPC_URL .env | cut -d '=' -f2)

# Check if RPC_URL is empty
if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL is not set in the .env file"
    exit 1
fi

echo "Using RPC URL: $RPC_URL"

# Extract chain ID from RPC_URL
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL)
echo "Chain ID: $CHAIN_ID"

# List of contracts to verify
contracts=("YnLSDe" "assetRegistry" "eigenStrategyManager" "tokenStakingNodesManager" "ynEigenDepositAdapter" "rateProvider" "ynEigenViewer")

# Map contracts to their Solidity contract names
declare -A solidity_contracts=(
    ["YnLSDe"]="ynEigen"
    ["assetRegistry"]="AssetRegistry"
    ["eigenStrategyManager"]="EigenStrategyManager"
    ["tokenStakingNodesManager"]="TokenStakingNodesManager"
    ["ynEigenDepositAdapter"]="ynEigenDepositAdapter"
    ["rateProvider"]="LSDRateProvider"
    ["ynEigenViewer"]="ynEigenViewer"
)

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
    local solidity_contract=${solidity_contracts[$contract_name]}
    if [ -z "$solidity_contract" ]; then
        echo "Error: No Solidity contract name found for $contract_name"
        return 1
    fi

    echo "Verifying $contract_name (Solidity contract: $solidity_contract)..."

    # Verify the implementation contract
    forge verify-contract $impl_address $solidity_contract \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --rpc-url $RPC_URL

    # # Verify the proxy contract
    # local proxy_admin=$(jq -r '.upgradeTimelock' "$DEPLOYMENT_FILE")
    # forge verify-contract \
    #     --constructor-args $(cast abi-encode "constructor(address,address,bytes)" $impl_address $proxy_admin "0x") \
    #     $proxy_address TransparentUpgradeableProxy \
    #     --etherscan-api-key $ETHERSCAN_API_KEY \
    #     --rpc-url https://holesky.infura.io/v3/
}


# Verify each contract
for contract in "${contracts[@]}"; do
    read proxy impl proxy_admin <<< $(extract_addresses $contract)
    verify_contract $proxy $impl $proxy_admin $contract
done
Verify TokenStakingNode implementation
token_staking_node_impl=$(jq -r '.tokenStakingNodeImplementation' "$DEPLOYMENT_FILE")
forge verify-contract $token_staking_node_impl TokenStakingNode \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url $RPC_URL

# Define delay based on chain ID
if [ "$CHAIN_ID" = "17000" ]; then
    delay=$((15 * 60))  # 15 minutes in seconds
elif [ "$CHAIN_ID" = "1" ]; then
    delay=$((3 * 24 * 60 * 60))  # 3 days in seconds
else
    echo "Unsupported chain ID: $CHAIN_ID"
    exit 1
fi
echo "Timelock delay: $delay seconds"


# Load YNDev and YNSecurityCouncil addresses from deployment file
YNDev=$(jq -r '.YNDev' "$DEPLOYMENT_FILE")
YNSecurityCouncil=$(jq -r '.YnSecurityCouncil' "$DEPLOYMENT_FILE")

# Create arrays for proposers and executors
proposers=($YNDev)
executors=($YNSecurityCouncil)

# Log proposers and executors
echo "Proposers:"
for proposer in "${proposers[@]}"; do
    echo "  $proposer"
done

echo "Executors:"
for executor in "${executors[@]}"; do
    echo "  $executor"
done

# Encode constructor arguments; assumes only one of each.
constructor_args=$(cast abi-encode "constructor(uint256,address[],address[],address)" $delay "[$YNDev]" "[$YNSecurityCouncil]" $YNSecurityCouncil)

echo "Timelock constructor arguments: $constructor_args"

# Verify TimelockController
timelock_address=$(jq -r '.upgradeTimelock' "$DEPLOYMENT_FILE")
forge verify-contract $timelock_address TimelockController \
     --constructor-args $constructor_args \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --rpc-url $RPC_URL

echo "Verification process completed."


