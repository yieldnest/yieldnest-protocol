#!/bin/bash
source .env

set -e

######################
## GLOBAL VARIABLES ##
######################

# Read the Etherscan API key from .env file
ETHERSCAN_API_KEY=$(grep ETHERSCAN_API_KEY .env | cut -d '=' -f2)
# Read the RPC URL from .env file
RPC_URL=$(grep RPC_URL .env | cut -d '=' -f2)

PRIVATE_KEY=""

###############
## FUNCTIONS ##
###############

function display_help() {
    delimitier
    echo "Please enter the relative file path to the input json."
    delimitier
}

function delimitier() {
    echo '#################################################'
}

function simulate() {
    forge script $1 -s $2 --rpc-url $3
}

function broadcast() {
    forge script $1 -s $2 --rpc-url $3 --broadcast
}

function verify() {
    forge script $1 -s $2 --rpc-url $3 --broadcast
}

function deploy() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "run(string)" "/$INPUT_JSON")
    if [[ $CHAIN == 31337 ]]; then
        PRIVATE_KEY=$(grep ANVIL_ONE .env | cut -d '=' -f2)
    fi
    echo "$1"
    broadcast script/ynEigenDeployer/YnEigenDeployer.sol:YnEigenDeployer $CALLDATA $RPC_URL

}
if [[ "$1" == "" ]]; then
    echo "$1"
    display_help
else
    echo "DEPLOYING..."
    deploy $1
fi

echo "script finished"
exit 0
