const fs = require('fs');
const contractAddresses = require('./contractAddresses');
const { deployAndInitializeTransparentUpgradeableProxy, deployProxy, upgradeProxy, getProxyImplementation, retryVerify } = require('./utils');

async function main() {

    const goerliAddresses = JSON.parse(fs.readFileSync('./goerli-addresses.json', 'utf8'));
    const stakingNodesManager = await ethers.getContractAt('StakingNodesManager', goerliAddresses.stakingNodesManager);

    const tx = await stakingNodesManager.createStakingNode();
    const receipt = await tx.wait();

    console.log(`Staking node created with transaction hash: ${receipt.transactionHash}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
