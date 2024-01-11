const fs = require('fs');
const hre = require('hardhat');
require('dotenv').config();


const fetch = (...args) => import('node-fetch').then(({default: fetch}) => fetch(...args));


async function getValidators({ apiKey }) {

    const url = "https://hubble.figment.io/api/v1/prime/eth2_staking/provision";

    const options = {
        method: 'POST',
        headers: {
            'Accept': 'application/json',
            'Authorization': apiKey,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ eth2_network_name: "goerli" })
    };

    const response = await fetch(url, options);
    const data = await response.json();

    return data;
}

async function getNetworkState({ apiKey }) {

    const url = 'https://eth-network.datahub.figment.io/v3/ethereum/network_overview?history=false&chain_id=goerli';


    const options = {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `${apiKey}`
        }
    };

    const response = await fetch(url, options);
    const data = await response.json();

    return data;
}



async function getFigmentValidators() {
    const [deployer] = await hre.ethers.getSigners();
    const apiKey = process.env.FIGMENT_API_KEY;

    console.log(`Figment API Key: |${apiKey}|`);

    const networkState = await getNetworkState({ apiKey });

    console.log(`Data: ${JSON.stringify(networkState)}`);


    const validators = await getValidators({ apiKey });

    console.log(validators);
}

module.exports = {
    getFigmentValidators
}

if (require.main === module) {
    getFigmentValidators()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}

