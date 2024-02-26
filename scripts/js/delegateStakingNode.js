const fs = require('fs');
const contractAddresses = require('./contractAddresses');
const { deployAndInitializeTransparentUpgradeableProxy, deployProxy, upgradeProxy, getProxyImplementation, retryVerify } = require('./utils');

async function main() {

    const goerliAddresses = JSON.parse(fs.readFileSync('./goerli-addresses.json', 'utf8'));
    const stakingNodesManager = await ethers.getContractAt('StakingNodesManager', goerliAddresses.stakingNodesManager);


    const delegationManager = await stakingNodesManager.delegationManager();
    const ynETH = await stakingNodesManager.ynETH();

    console.log({
        delegationManager,
        ynETH
    })

    const nodeIndex = 0;
    console.log(`Node index: ${nodeIndex}`);

    const nodeAddress = await stakingNodesManager.nodes(nodeIndex);

    const delegationManagerFromNode = await stakingNodesManager.delegationManager();
    console.log(`Delegation Manager from node: ${delegationManagerFromNode}`);

    console.log(`Node address: ${nodeAddress}`);

    const stakingNode = await ethers.getContractAt('StakingNode', nodeAddress);


    const eigenPodAddress = await stakingNode.eigenPod();
    console.log(`EigenPod address: ${eigenPodAddress}`);
    const delegateAddress = '0x234649b2D3c67E74f073F9C95Fa8b10846c93a6b';
    
    await stakingNode.delegate(delegateAddress);
    console.log(`Delegated to: ${delegateAddress}`);


}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
