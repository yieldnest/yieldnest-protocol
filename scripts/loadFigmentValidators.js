const fs = require('fs');
const hre = require('hardhat');
require('dotenv').config();


const fetch = (...args) => import('node-fetch').then(({default: fetch}) => fetch(...args));



async function getStakeFishValidators() {
    const [deployer] = await hre.ethers.getSigners();

    const sdk = require('api')('@figment-api/v1.0#11wm1w2lnt40b50');

    console.log(`Figment API Key: |${process.env.FIGMENT_API_KEY}|`);

    console.log(`Response: ${await sdk.getV3EthereumNetwork_overview({history: 'false', chain_id: 'mainnet', authorization: 'your-api-key-here' }) }`);

    const data = await sdk.getApiV1PrimeEth2_stakingValidators({'page[number]': '1', authorization: process.env.FIGMENT_API_KEY })
    console.log({
        data
    });
}

module.exports = {
    getStakeFishValidators
}

if (require.main === module) {
    getStakeFishValidators()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}

