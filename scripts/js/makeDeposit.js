const fs = require('fs');
const hre = require("hardhat");

async function main() {

    const [depositor] = await hre.ethers.getSigners();

    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json'));
    const ynETH = await hre.ethers.getContractAt("ynETH", addresses.ynETH);
    const depositAmount = hre.ethers.utils.parseEther("32"); // 32 ETH
    console.log(`Starting deposit for ${depositor.address}`);
    await ynETH.depositETH(depositor.address, { value: depositAmount });
    console.log('Deposit completed');
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

