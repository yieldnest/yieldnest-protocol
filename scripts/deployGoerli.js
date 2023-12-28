
const hre = require("hardhat");
const fs = require('fs');
const contractAddresses = require('./contractAddresses');
const { deployAndInitializeTransparentUpgradeableProxy, deployProxy, upgradeProxy } = require('./utils');

const { deploy } = require('./deploy');

async function main() {

    const { ynETH, oracle, stakingNodesManager } = await deploy();
    console.log("Verifying contracts on etherscan");
    async function retryVerify(contractName, contractAddress, constructorArguments) {
        while (true) {
            try {
                await hre.run("verify:verify", {
                    address: contractAddress,
                    constructorArguments: constructorArguments,
                });
                console.log(`${contractName} verified successfully`);
                break;
            } catch (error) {
                console.error(`Error verifying ${contractName}, retrying in 10 seconds`, error);
                await new Promise(resolve => setTimeout(resolve, 10000));
            }
        }
    }

    await retryVerify("ynETH", ynETH.address, []);
    await retryVerify("Oracle", oracle.address, []);
    await retryVerify("StakingNodesManager", stakingNodesManager.address, []);
    console.log("Contracts verified successfully");

    const addresses = {
        ynETHContract: ynETHContract.address,
        oracle: oracle.address
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
