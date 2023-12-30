async function main() {
    const fs = require('fs');
    const yargs = require('yargs/yargs');
    const { hideBin } = require('yargs/helpers');
    const argv = yargs(hideBin(process.argv)).argv;

    const contractName = argv.contract;
    if (!contractName) {
        console.error('Please provide --contract parameter');
        process.exit(1);
    }

    const goerliAddresses = JSON.parse(fs.readFileSync('./goerli-addresses.json', 'utf8'));
    
    const key = contractName.charAt(0).toLowerCase() + contractName.slice(1);
    const contractAddress = goerliAddresses[key];
    if (!contractAddress) {
        console.error(`No contract found with name ${contractName}`);
        process.exit(1);
    }

    const factory = await ethers.getContractFactory(contractAddress);

    const contract = await ethers.getContractAt('TransparentUpgradeableProxy', contractAddress);
    ynETH = await upgradeProxy(
        contract,
        factory,
        contractName,
        [{
          admin: deployer.address,
          stakingNodesManager: stakingNodesManager.address,
          oracle: oracle.address,
          wETH: weth.address
        }]
    );
    await ynETH.deployed();
}

main().catch(e => {
    console.error(e);
    process.exit(1);
});

