const hre = require("hardhat");
const fs = require("fs");

async function main() {
    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json'));
    const stakingNodesManager = await hre.ethers.getContractAt("StakingNodesManager", addresses.stakingNodesManager);
    const stakingNodeAddress = await stakingNodesManager.nodes(0);
    const stakingNode = await hre.ethers.getContractAt("StakingNode", stakingNodeAddress);
    const tx = await stakingNode.queueWithdrawals(hre.ethers.utils.parseEther("32"));
    await tx.wait();
    console.log(`Queued withdrawals for 32 ETH shares to staking node 0.`);
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}


