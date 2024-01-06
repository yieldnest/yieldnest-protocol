const fs = require('fs');
const { ethers } = require("hardhat");

async function main() {
    const goerliAddresses = JSON.parse(fs.readFileSync('./goerli-addresses.json', 'utf8'));
    const stakingNodesManagerAddress = goerliAddresses['stakingNodesManager'];
    if (!stakingNodesManagerAddress) {
        console.error('No stakingNodesManager found in goerli-addresses.json');
        process.exit(1);
    }

    const ynViewerAddress = goerliAddresses['ynViewer'];
    if (!ynViewerAddress) {
        console.error('No ynViewer found in goerli-addresses.json');
        process.exit(1);
    }
    const ynViewer = await ethers.getContractAt('ynViewer', ynViewerAddress);
    const validators = await ynViewer.getAllValidators();

    const StakingNodesManager = await ethers.getContractAt('StakingNodesManager', stakingNodesManagerAddress);

    console.log(`Total validators: ${validators.length}`);

    validators.forEach((validatorAddress, i) => {
        console.log(`Validator ${i}: ${validatorAddress}`);
    });

    const nodeCount = await StakingNodesManager.nodesLength();

    console.log(`Total nodes: ${nodeCount}`);

    for (let i = 0; i < nodeCount; i++) {
        const nodeAddress = await StakingNodesManager.nodes(i);
        console.log(`Node ${i}: ${nodeAddress}`);

        const stakingNode = await ethers.getContractAt('StakingNode', nodeAddress);

        const testFoo = await stakingNode.testFoo();
        console.log(`Test Foo for Node ${i}: ${testFoo}`);

        const eigenPodAddress = await stakingNode.eigenPod();
        console.log(`EigenPod address: ${eigenPodAddress}`);
        const eigenPod = await ethers.getContractAt('IEigenPod', eigenPodAddress);
        const ownerAddress = await eigenPod.podOwner();
        console.log(`Owner of EigenPod ${i}: ${ownerAddress}`);

        const withdrawableRestakedGwei = await eigenPod.withdrawableRestakedExecutionLayerGwei();
        console.log(`Withdrawable Restaked Gwei for EigenPod ${i}: ${withdrawableRestakedGwei}`);
        const maxRestakedBalanceGwei = await eigenPod.MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR();
        console.log(`Max Restaked Balance Gwei per Validator for EigenPod ${i}: ${maxRestakedBalanceGwei}`);
        const nonBeaconChainETHBalanceWei = await eigenPod.nonBeaconChainETHBalanceWei();
        console.log(`Non Beacon Chain ETH Balance Wei for EigenPod ${i}: ${nonBeaconChainETHBalanceWei}`);

        const hasRestaked = await eigenPod.hasRestaked();
        console.log(`Has Restaked for EigenPod ${i}: ${hasRestaked}`);
        const eigenPodManager = await eigenPod.eigenPodManager();
        console.log(`EigenPod Manager for EigenPod ${i}: ${eigenPodManager}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
