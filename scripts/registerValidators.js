const { retryVerify, getProxyImplementation } = require('./utils');
const { getStakeFishValidators } = require('./stakefish-validators-load');
const fs = require('fs');
const hre = require("hardhat");

async function main() {
    const validators = await getStakeFishValidators();


    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));
    const StakingNodesManagerAddress = addresses.StakingNodesManager;

    const StakingNodesManager = await hre.ethers.getContractFactory("StakingNodesManager");
    const stakingNodesManager = StakingNodesManager.attach(StakingNodesManagerAddress);

    await stakingNodesManager.registerValidators(validators);

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

