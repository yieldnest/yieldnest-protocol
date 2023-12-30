const { retryVerify, getProxyImplementation } = require('./utils');
const { getStakeFishValidators } = require('./loadStakefishValidators');
const fs = require('fs');
const hre = require("hardhat");

async function main() {
    const validators = await getStakeFishValidators();


    console.log(`Obtained validators: ${validators.length}`);

    /*
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
    */

        /*
          pubkeys: '0x9956af8bbb06670e427fa2d9e49e7c83ad3cc6ce4d9ae68125a2ad099f79fd0cd34ad7b556112b34a5851aa0a4ce6f31',
  withdrawal_credentials: '0x010000000000000000000000a1237efe3159197537f41f510f01d09394780f08',
  signatures: '0x948394f10130fce7f86306bda1b16c09b8a1638ca7c4d0fa4602b33d86432ffc44abc8d5ecbf26d2d03357c43234fd23165a54dafe2dfe7a1c202e67a8aa251a3d3a432a32f02cebeecf1c80b8421422215034ad601894edd6ee3af8cdb6a4d7',
  deposit_data_roots: [
    '0x845c46e3289bcf254577a782451dc0c9a0684cdf749c5bc2dd1c7ae616266c0e'
  ]
}
        */

    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));

    console.log({
        stakingNodesManagerAddress: addresses.stakingNodesManager
    });

    const stakingNodesManager = await hre.ethers.getContractAt("StakingNodesManager", addresses.stakingNodesManager);


    const depositRoot = '0x' + '00'.repeat(32);


    const validatorData = [];
    for (const validator of validators) {
        
        validatorData.push({
            publicKey: validator.pubkeys,
            signature: validator.signatures,
            depositDataRoot: validator.depositDataRoot
        });
    }

    const nodeId = await stakingNodesManager.getNextNodeIdToUse();
    console.log('Getting withdrawal credentials...', nodeId);
    const withdrawalCredentials = await stakingNodesManager.getWithdrawalCredentials(nodeId);

    console.log('Generating deposit data root for each deposit data...');
    for (const data of validatorData) {
    
        const amount = ethers.utils.parseEther('32');
        const depositRoot = await stakingNodesManager.generateDepositRoot(data.publicKey, data.signature, withdrawalCredentials, amount);

        console.log({
            depositRoot,
            data: data.depositDataRoot
        })

       // const depositDataRoot = await stakingNodesManager.generateDepositRoot(data.publicKey, data.signature, withdrawalCredentials, amount);
       data.depositDataRoot = depositRoot;
    }


    console.log(`Pushing validator data:`, validatorData);

    await stakingNodesManager.registerValidators(depositRoot, validatorData);

    console.log('Done');

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

