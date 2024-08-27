#!/bin/bash
source .env

set -e

######################
## GLOBAL VARIABLES ##
######################

# Read the Etherscan API key from .env file
ETHERSCAN_API_KEY=$(grep ETHERSCAN_API_KEY .env | cut -d '=' -f2)
# Read the RPC URL from .env file
INFURA_PROJECT_ID=$(grep INFURA_PROJECT_ID .env | cut -d '=' -f2)
DEPLOYER_ADDRESS=$(grep DEPLOYER_ADDRESS .env | cut -d '=' -f2)
PRIVATE_KEY=""

# verify env variables
if [[ -z $ETHERSCAN_API_KEY || -z $INFURA_PROJECT_ID || -z $DEPLOYER_ADDRESS ]]; then
    echo "invalid .env vars"
    exit 1
fi
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
    forge script $1 -s $2 --rpc-url $3 --account yieldnestDeployerKey --sender $DEPLOYER_ADDRESS
}

function broadcast() {
    forge script $1 -s $2 --rpc-url $3 --account yieldnestDeployerKey --sender $DEPLOYER_ADDRESS --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
}
function simulator() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "run(string)" "/$INPUT_JSON")
    INFURA_ADDRESS=""

    if [[ $CHAIN == 1 ]]; then
        INFURA_ADDRESS=https://mainnet.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 17000 ]]; then
        INFURA_ADDRESS=https://holesky.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 31337 ]]; then
        INFURA_ADDRESS=http://127.0.0.1:8545
    else
        exit 1
    fi

    simulate script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $INFURA_ADDRESS
}
function verify() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "verify(string)" "/$INPUT_JSON")
    INFURA_ADDRESS=""

    if [[ $CHAIN == 1 ]]; then
        INFURA_ADDRESS=https://mainnet.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 17000 ]]; then
        INFURA_ADDRESS=https://holesky.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 31337 ]]; then
        INFURA_ADDRESS=http://127.0.0.1:8545
    else
        exit 1
    fi

    broadcast script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $INFURA_ADDRESS
}
function deploy() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "run(string)" "/$INPUT_JSON")
    INFURA_ADDRESS=""

    if [[ $CHAIN == 1 ]]; then
        INFURA_ADDRESS=https://mainnet.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 17000 ]]; then
        INFURA_ADDRESS=https://holesky.infura.io/v3/$INFURA_PROJECT_ID
    elif [[ $CHAIN == 31337 ]]; then
        INFURA_ADDRESS=http://127.0.0.1:8545
    else
        exit 1
    fi

    broadcast script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $INFURA_ADDRESS

}
if [[ "$1" == "" ]]; then
    echo "$1"
    display_help
else
    delimitier
    read -p "Would you like to VERIFY an existing deployment or DEPLOY a new ynLSD?  VERIFY/DEPLOY " DEPLOY
    case $DEPLOY in
    deploy | DEPLOY | [Dd]*)
        delimitier
        read -p "Would you like to simulate this transaction before deployment? y/n " CONFIRMATION

        case $CONFIRMATION in
        [Yy]*)
            echo "Simulating..."
            simulator $1
            ;;
        [Nn]*)
            echo "Deploying..."
            ;;
        esac
        delimitier
        read -p "Would you like to continue deploying? y/n " DEPLOYMENT
        case $DEPLOYMENT in
        [Yy]*)
            echo "Deploying..."
            deploy $1
            ;;
        [Nn]*)
            echo "Exiting."
            exit 0
            ;;
        esac
        ;;
    [vV] | VERIFY | verify)
        echo "Verifying..."
        verify $1
        ;;
    *)
        echo "Invalid input"
        exit 1
        ;;
    esac
fi

echo "script finished"
exit 0
