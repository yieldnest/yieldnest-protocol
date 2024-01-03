const { upgradeProxy, getProxyImplementation, retryVerify } = require('./utils');
const fs = require('fs');


async function upgradeContract({ contractName }) {


    console.log('Starting the upgrade process...');
    if (!contractName) {
        console.error('Please provide contract parameter');
        process.exit(1);
    }
    console.log(`Contract name provided: ${contractName}`);

    const goerliAddresses = JSON.parse(fs.readFileSync('./goerli-addresses.json', 'utf8'));
    console.log('Loaded goerli addresses');

    const key = contractName.charAt(0).toLowerCase() + contractName.slice(1);
    const contractAddress = goerliAddresses[key];
    if (!contractAddress) {
        console.error(`No contract found with name ${key}`);
        process.exit(1);
    }
    console.log(`Contract address found: ${contractAddress}`);

    const factory = await ethers.getContractFactory(`Testnet${contractName}`);
    console.log('Contract factory obtained');

    const contract = await ethers.getContractAt('TransparentUpgradeableProxy', contractAddress);

    const implementation = await getProxyImplementation(contract);
    console.log(`Implementation address found: ${implementation}`);

    
    console.log('Contract instance obtained');
    const upgraded = await upgradeProxy(
        contract,
        factory,
        contractName
    );
    console.log('Upgrade process initiated');
    await upgraded.deployed();
    console.log('Upgrade process completed');

    const newImplementation = await getProxyImplementation(upgraded);
    console.log(`New implementation address: ${newImplementation}`);

    console.log('Starting verification process...');
    await retryVerify(contractName, newImplementation, []);
}

module.exports = {
    upgradeContract
}


if (require.main === module) {
    upgradeContract({ contractName: process.env.CONTRACT })
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}
