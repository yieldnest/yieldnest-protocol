import fs from 'fs';
import hre from "hardhat";

import fetch from 'node-fetch';

async function main() {
    const [deployer] = await hre.ethers.getSigners();


    
    const walletAddress = "0xA1237efe3159197537f41F510F01D09394780f08";
    const walletUrl = `https://fee-pool-api-goerli.oracle.ethereum.fish/wallet/${walletAddress}/validators?limit=40&offset=0`;
    const validatorsResponse = await fetch(walletUrl, {
    "headers": {
        "accept": "application/json, text/plain, */*",
        "accept-language": "en-US,en;q=0.5",
        "sec-ch-ua": "\"Brave\";v=\"119\", \"Chromium\";v=\"119\", \"Not?A_Brand\";v=\"24\"",
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": "\"macOS\"",
        "sec-fetch-dest": "empty",
        "sec-fetch-mode": "cors",
        "sec-fetch-site": "cross-site",
        "sec-gpc": "1",
        "Referer": "https://stake.fish/",
        "Referrer-Policy": "no-referrer-when-downgrade"
    },
    "body": null,
    "method": "GET"
    });

    const validators = await validatorsResponse.json();

    console.log(JSON.stringify(validators, null, 2));

    const options = await fetch("https://fee-pool-api-goerli.oracle.ethereum.fish/staking/prepare-deposit", {
        "headers": {
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "cross-site",
            "Referer": "https://stake.fish/",
            "Referrer-Policy": "no-referrer-when-downgrade"
        },
        "body": null,
        "method": "OPTIONS"
    });
    
    console.log({
        options
    })


    const rawMessage = "I confirm I would like to stake 1 validator(s) and this request is valid until 1703530364.";

    function prependEthereumSignedMessage(rawMessage) {
        return `\x19Ethereum Signed Message:\n${rawMessage.length}${rawMessage}`;
    }

    const message = prependEthereumSignedMessage("I confirm I would like to stake 1 validator(s) and this request is valid until 1703530364.");
    const messageHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(message));
    console.log(`Message Hash: ${messageHash}`);


    const signingKey = new ethers.utils.SigningKey('0x' + process.env.PRIVATE_KEY);
    const signature = signingKey.signDigest(messageHash);
    console.log(`Signature: ${ethers.utils.hexlify(signature)}`);


    const body = {
        "depositor_address": "0xA1237efe3159197537f41F510F01D09394780f08",
        "withdrawal_address": "0xA1237efe3159197537f41F510F01D09394780f08",
        "deposit_count": 1,
        "signed_message": {
            "message_hash": "0x153c15c5ebe2039b9aaf019f345a521eb20997cf37628e702d8c0918b4b618e8",
            "signature": "0xf26e5d2c7808cdd412df2100b611b9ac1141c7171977e8e999d3a3b7e00b7ac675a5b998d16aa3ab4aab8bcad6552f58b756596ae0dea0f3753326fbc119afe91b",
            "valid_until": 1703530364
        }
    };

    const responseDeposit = await fetch("https://fee-pool-api-goerli.oracle.ethereum.fish/staking/prepare-deposit", {
        "headers": {
            "accept": "application/json, text/plain, */*",
            "accept-language": "en-US,en;q=0.5",
            "content-type": "application/json; charset=UTF-8",
            "sec-ch-ua": "\"Brave\";v=\"119\", \"Chromium\";v=\"119\", \"Not?A_Brand\";v=\"24\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"macOS\"",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "cross-site",
            "sec-gpc": "1",
            "Referer": "https://stake.fish/",
            "Referrer-Policy": "no-referrer-when-downgrade"
        },
        "body": JSON.stringify(body),
        "method": "POST"
    });



    console.log({
        responseDeposit: await responseDeposit.json()
    })
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

