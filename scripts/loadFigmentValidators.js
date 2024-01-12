const fs = require('fs');
const hre = require('hardhat');
require('dotenv').config();


const fetch = (...args) => import('node-fetch').then(({default: fetch}) => fetch(...args));


async function requestValidators({ apiKey, count, withdrawalAddress }) {

    const url = "https://hubble.figment.io/api/v1/prime/eth2_staking/provision";

    const options = {
        method: 'POST',
        headers: {
            'Accept': 'application/json',
            'Authorization': apiKey,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            eth2_network_name: "goerli",
            "withdrawal_address": withdrawalAddress,
            "region": "ca-central-1",
            "validators_count": count
         })
    };

    const response = await fetch(url, options);
    const data = await response.json();

    return data;
}

async function listValidators ({ apiKey, withdrawalAddress }) {

        const urlParams = {
            withdrawal_address: withdrawalAddress,
            eth2_network_name: "goerli",
            status: "provisioned",
            "page[number]": 1
        };
        const url = "https://hubble.figment.io/api/v1/prime/eth2_staking/validators?" + new URLSearchParams(urlParams).toString();

        console.log({
            url
        });

        const options = {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'Authorization': apiKey
            }
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
            'Authorization': `${apiKey}`,
            "withdrawal_address": "0x27Bf18B87c52Efd24E7Cc20F36c18Ef7Eb64ae95",
            "region": "ca-central-1",
            "validators_count": 1
        }
    };

    const response = await fetch(url, options);
    const data = await response.json();

    return data;
}


async function pollForValidators({ apiKey, withdrawalAddress, validatorCount }) {
    let validators;

    while (true) {
        const listedValidators = await listValidators({ apiKey, withdrawalAddress }); 

        validators = listedValidators.data;

        if (validators.length >= validatorCount) {
            break;
        }

        await new Promise(resolve => setTimeout(resolve, 5000));
    }

    const processedValidators = validators.map(v => {
        return {
            publicKey: '0x' + v.attributes.pubkey,
            signature: '0x' + v.attributes.signature,
            depositDataRoot: '0x' + v.attributes.deposit_data_root
        }
    })


    return processedValidators;
}



async function getFigmentValidators({ withdrawalAddress, count }) {
    const [deployer] = await hre.ethers.getSigners();
    const apiKey = process.env.FIGMENT_API_KEY;

    console.log(`Figment API Key: |${apiKey}|`);

    const networkState = await getNetworkState({ apiKey });

    console.log(`Data: ${JSON.stringify(networkState)}`);


    withdrawalAddress =  withdrawalAddress || "0x27Bf18B87c52Efd24E7Cc20F36c18Ef7Eb64ae95";
    const validatorCount = count;

    let validators = await pollForValidators({ apiKey, withdrawalAddress, validatorCount: 0 });

    console.log(`Validators length: ${validators.length}. Needed ${validatorCount}`);

    const extraValidatorsNeededCount = Math.max(0, validatorCount - validators.length);

    if (extraValidatorsNeededCount === 0) {

        console.log(`Loaded ${validators.length}. Finished.`);
        return validators;
    }

    console.log(`Insufficient validators. Need extra ${extraValidatorsNeededCount}. Requesting validators.`);

    const futureValidators = await requestValidators({ apiKey, withdrawalAddress, count: extraValidatorsNeededCount });


    validators = await pollForValidators({ apiKey, withdrawalAddress, validatorCount });


    console.log(`Loaded ${validators.length}`);


    return validators;

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

