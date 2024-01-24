

async function main() {

    const contractAddress = '0x8B71140AD2e5d1E7018d2a7f8a288BD3CD38916F';
    const contract = await ethers.getContractAt('IEtherFiNodesManager', contractAddress);

    const latestBlock = await ethers.provider.getBlockNumber();
    const toBlock = latestBlock - 2000;
    const fromBlock = latestBlock - 10000;
    const filter = contract.filters.PhaseChanged();
    const logs = await contract.queryFilter(filter, fromBlock, toBlock);
    
    const validatorIds =  [...new Set(logs.map(log => log.args._validatorId))];
    console.log(`Count of Unique Validator Ids: ${validatorIds.length}`);
    
    const withdrawalSafeAddresses = new Set();
    const batchSize = 25;
    const safeAddressToIds = {};
    for (let i = 0; i < validatorIds.length; i += batchSize) {
        const batchIds = validatorIds.slice(i, i + batchSize);
        console.log(`Processing batch ${i/batchSize + 1} of ${Math.ceil(validatorIds.length/batchSize)}`);
        const batchPromises = batchIds.map(async id => {
            const address = await contract.etherfiNodeAddress(id);
            if (!safeAddressToIds[address]) {
                safeAddressToIds[address] = [];
            }
            safeAddressToIds[address].push(id);
            return address;
        });
        const batchAddresses = await Promise.all(batchPromises);
        batchAddresses.forEach(address => withdrawalSafeAddresses.add(address));
        console.log(`Batch ${i/batchSize + 1} processed`);
    }
    console.log(`Count of Unique Withdrawal Safe Addresses: ${withdrawalSafeAddresses.size}`);
    console.log(`Unique Withdrawal Safe Addresses: ${[...withdrawalSafeAddresses]}`);


    const MAX_COUNT_FOR_PRINTED_EIGENPOD_DATA = 1000000;

    const withdrawalSafeAddressesArray = [...withdrawalSafeAddresses];
    for (let i = 0; i < Math.min(MAX_COUNT_FOR_PRINTED_EIGENPOD_DATA, withdrawalSafeAddressesArray.length); i++) {
        const nodeAddress = withdrawalSafeAddressesArray[i];
        console.log(`Processing node at address: ${nodeAddress} for EigenPod ${i}`);

        const validatorIdsForAddress = safeAddressToIds[nodeAddress];
        console.log(`Validators for node at address: ${nodeAddress} are ${validatorIdsForAddress}`);

        const node = await ethers.getContractAt('IEtherFiNode', nodeAddress);
        const etherFiNodesManagerAddress = await node.etherFiNodesManager();
        console.log(`EtherFiNodesManager for node at address: ${nodeAddress} is ${etherFiNodesManagerAddress}`);

        const stakingStartTimestamp = await node.stakingStartTimestamp();
        console.log(`Staking Start Timestamp for node at address: ${nodeAddress} is ${stakingStartTimestamp}`);


        const isRestakingEnabled = await node.isRestakingEnabled();
        if (!isRestakingEnabled) {
            console.log(`Skipping node at address: ${nodeAddress} as restaking is not enabled`);
            continue;
        }

        console.log(`Processing node at address: ${nodeAddress} with restaking enabled`);

        const eigenPodAddress = await node.eigenPod();
        const eigenPod = await ethers.getContractAt('IEigenPod09062023', eigenPodAddress);

        console.log(`EigenPod Address for EigenPod ${i}: ${eigenPodAddress}`);

        const requiredBalanceGwei = await eigenPod.REQUIRED_BALANCE_GWEI();
        console.log(`Required Balance Gwei for EigenPod ${i}: ${requiredBalanceGwei}`);
        const requiredBalanceWei = await eigenPod.REQUIRED_BALANCE_WEI();
        console.log(`Required Balance Wei for EigenPod ${i}: ${requiredBalanceWei}`);
        const restakedExecutionLayerGwei = await eigenPod.restakedExecutionLayerGwei();
        console.log(`Restaked Execution Layer Gwei for EigenPod ${i}: ${restakedExecutionLayerGwei}`);
        const eigenPodManager = await eigenPod.eigenPodManager();
        console.log(`EigenPod Manager for EigenPod ${i}: ${eigenPodManager}`);
        const podOwner = await eigenPod.podOwner();
        console.log(`Pod Owner for EigenPod ${i}: ${podOwner}`);

        const hasRestaked = await eigenPod.hasRestaked();
        console.log(`Has Restaked for EigenPod ${i}: ${hasRestaked}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });


