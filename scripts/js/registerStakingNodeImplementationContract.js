const hre = require("hardhat");
const fs = require('fs');
const { retryVerify } = require('./utils');

async function main() {
    const StakingNode = await hre.ethers.getContractFactory("StakingNode");
    const stakingNode = await StakingNode.deploy();

    await stakingNode.deployed();

    console.log("StakingNode deployed to:", stakingNode.address);


    const goerliAddresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));
    const stakingNodeManagerAddress = goerliAddresses["stakingNodesManager"];

    const StakingNodeManager = await hre.ethers.getContractFactory("StakingNodesManager");
    const stakingNodeManager = await hre.ethers.getContractAt("StakingNodesManager", stakingNodeManagerAddress);

    await stakingNodeManager.registerStakingNodeImplementationContract(stakingNode.address);
    console.log("StakingNode implementation contract registered");

    console.log("Retry verify for new deployment: ");
    await retryVerify('StakingNode', stakingNode.address, []);

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
