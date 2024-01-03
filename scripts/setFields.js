const fs = require('fs');
const hre = require("hardhat");


async function main() {

    const [depositor] = await hre.ethers.getSigners();

    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json'));
    const stakingNodesManager = await hre.ethers.getContractAt("TestnetStakingNodesManager", addresses.stakingNodesManager);

    const networkName = hre.network.name === 'hardhat' ? 'goerli' : hre.network.name;
    const existingAddresses = require('./contractAddresses')[networkName];
    const delegationManagerAddress = existingAddresses.EIGENLAYER_DELEGATION_MANAGER_ADDRESS;
    await stakingNodesManager.setDelegationManager(delegationManagerAddress);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

