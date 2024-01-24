

async function main() {

    const contractAddress = '0x8B71140AD2e5d1E7018d2a7f8a288BD3CD38916F';
    const contract = await ethers.getContractAt('IEtherFiNodesManager', contractAddress);

    const latestBlock = await ethers.provider.getBlockNumber();
    const fromBlock = latestBlock - 10000;
    const filter = contract.filters.PhaseChanged();
    const logs = await contract.queryFilter(filter, fromBlock, latestBlock);
    
    const validatorIds = [...new Set(logs.map(log => log.args._validatorId))];
    
    const withdrawalSafeAddresses = new Set();
    const batchSize = 25;
    for (let i = 0; i < validatorIds.length; i += batchSize) {
        const batchIds = validatorIds.slice(i, i + batchSize);
        console.log(`Processing batch ${i/batchSize + 1} of ${Math.ceil(validatorIds.length/batchSize)}`);
        const batchPromises = batchIds.map(id => contract.getWithdrawalSafeAddress(id));
        const batchAddresses = await Promise.all(batchPromises);
        batchAddresses.forEach(address => withdrawalSafeAddresses.add(address));
        console.log(`Batch ${i/batchSize + 1} processed`);
    }
    console.log(`Count of Unique Withdrawal Safe Addresses: ${withdrawalSafeAddresses.size}`);
    console.log(`Unique Withdrawal Safe Addresses: ${[...withdrawalSafeAddresses]}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });


