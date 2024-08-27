#!/bin/bash
source .env

set -e

######################
## GLOBAL VARIABLES ##
######################

# unset private key as we are reading it from cast wallet
PRIVATE_KEY=""
DEPLOYER_ACCOUNT_NAME=${DEPLOYER_ACCOUNT_NAME:-"yieldnestDeployerKey"}

# verify env variables
if [[ -z $ETHERSCAN_API_KEY || -z $RPC_URL || -z $DEPLOYER_ADDRESS ]]; then
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
    forge script $1 -s $2 --rpc-url $3 --account $DEPLOYER_ACCOUNT_NAME --sender $DEPLOYER_ADDRESS
}

function broadcast() {
    forge script $1 -s $2 --rpc-url $3 --account $DEPLOYER_ACCOUNT_NAME --sender $DEPLOYER_ADDRESS --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
}
function simulator() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "run(string)" "/$INPUT_JSON")

    simulate script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $RPC_URL
}
function verify() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "verify(string)" "/$INPUT_JSON")

    broadcast script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $RPC_URL
}
function deploy() {
    # the first argument should be the path to the JSON input file
    INPUT_JSON=$1
    CHAIN=$(jq -r ".chainId" "$INPUT_JSON")
    CALLDATA=$(cast calldata "run(string)" "/$INPUT_JSON")

    broadcast script/ynEigen/YnEigenScript.s.sol:YnEigenScript $CALLDATA $RPC_URL
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
