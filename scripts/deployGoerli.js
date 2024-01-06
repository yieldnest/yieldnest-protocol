
const hre = require("hardhat");
const fs = require('fs');
const contractAddresses = require('./contractAddresses');
const { deployAndInitializeTransparentUpgradeableProxy, deployProxy, upgradeProxy, getProxyImplementation, retryVerify } = require('./utils');

const { deploy } = require('./deploy');

async function main() {

    const { ynETH, oracle, stakingNodesManager, ynViewer } = await deploy();
    console.log("Verifying contracts on etherscan");

    const ynETHImpl = await getProxyImplementation(ynETH);
    const stakingNodesManagerImpl = await getProxyImplementation(stakingNodesManager);

    console.log({
        ynETHImpl: ynETHImpl,
        stakingNodesManagerImpl: stakingNodesManagerImpl
    })

    await retryVerify("ynETH", ynETHImpl, []);
    await retryVerify("Oracle", oracle.address, []);
    await retryVerify("StakingNodesManager", stakingNodesManagerImpl, []);
    await retryVerify("ynViewer", ynViewer.address, [ynETH.address, stakingNodesManager.address, oracle.address]);
    console.log("Contracts verified successfully");

    const addresses = {
        ynETH: ynETH.address,
        oracle: oracle.address,
        stakingNodesManager: stakingNodesManager.address
    };

    fs.writeFileSync('goerli-addresses.json', JSON.stringify(addresses, null, 2));
    console.log("Addresses written to goerli-addresses.json");

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
