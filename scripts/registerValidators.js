const { retryVerify, getProxyImplementation } = require('./utils');
const { getStakeFishValidators } = require('./loadStakefishValidators');
const { getFigmentValidators } = require('./loadFigmentValidators');

const fs = require('fs');
const hre = require("hardhat");

async function registerValidators() {



    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));

    console.log({
        stakingNodesManagerAddress: addresses.stakingNodesManager
    });

    const stakingNodesManager = await hre.ethers.getContractAt("StakingNodesManager", addresses.stakingNodesManager);

    const nodeId = await stakingNodesManager.getNextNodeIdToUse();
    console.log('Getting withdrawal credentials...', nodeId);
    const withdrawalCredentials = await stakingNodesManager.getWithdrawalCredentials(nodeId);

    const nodeAddress = await stakingNodesManager.nodes(nodeId);
    console.log(`Node ${nodeId}: ${nodeAddress}`);

    const stakingNode = await ethers.getContractAt('StakingNode', nodeAddress);

    const eigenPodAddress = await stakingNode.eigenPod();

    const validators = await getFigmentValidators({ withdrawalAddress: eigenPodAddress, count: 1 });

    console.log(`Obtained validators: ${validators.length}`);

    console.log(validators)


    const depositRoot = '0x' + '00'.repeat(32);


    const validatorData = [];
    for (const validator of validators) {
        
        validatorData.push({
            publicKey: validator.publicKey,
            signature: validator.signature,
            depositDataRoot: validator.depositDataRoot
        });
    }

    console.log('Generating deposit data root for each deposit data...');
    for (const data of validatorData) {
    
        const amount = ethers.utils.parseEther('32');

        console.log(data)
        const depositRoot = await stakingNodesManager.generateDepositRoot(data.publicKey, data.signature, withdrawalCredentials, amount);

        console.log({
            depositRoot,
            data: data.depositDataRoot
        })

       // const depositDataRoot = await stakingNodesManager.generateDepositRoot(data.publicKey, data.signature, withdrawalCredentials, amount);
       data.depositDataRoot = depositRoot;
    }


    console.log(`Pushing validator data:`, validatorData);

    return;

    const tx = await stakingNodesManager.registerValidators(depositRoot, validatorData);
    await tx.wait();

    console.log('Done');

}

async function main() {
    await registerValidators();
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = {
    registerValidators
}

