async function main() {
    const axios = require('axios');
    const fs = require('fs');
    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));
    const StakingNodesManager = await ethers.getContractAt('StakingNodesManager', addresses.stakingNodesManager);
    const nodeAddress = await StakingNodesManager.nodes(0);
    const stakingNode = await ethers.getContractAt('StakingNode', nodeAddress);
    const eigenPodAddress = await stakingNode.eigenPod();

    console.log(`Node Address: ${nodeAddress}`);
    console.log(`EigenPod Address: ${eigenPodAddress}`);
    console.log("Fetching proofs..");
    const url = `https://webserver.preprod.eigenops.xyz/api/v1/withdrawal-proofs/restake?eigenPodAddress=${eigenPodAddress}`;
    console.log(`URL: ${url}`);
    const response = await axios.get(url);
    const withdrawalProofs = response.data.verifyWithdrawalCredentialsCallParams;

    console.log({
        withdrawalProofs
    })
    console.log("Proofs obtained.");

    withdrawalProofs.stateRootProof.proof = withdrawalProofs.stateRootProof.stateRootProof;
    delete  withdrawalProofs.stateRootProof.stateRootProof;


    await stakingNode.verifyWithdrawalCredentials(
        withdrawalProofs.oracleTimestamp,
        withdrawalProofs.stateRootProof,
        withdrawalProofs.validatorIndices,
        withdrawalProofs.validatorFieldsProofs,
        withdrawalProofs.validatorFields
    );

    console.log('Done with proof submission');
}

if (require.main === module) {
    main().catch(error => {
        console.error(error);
        process.exit(1);
    });
}
