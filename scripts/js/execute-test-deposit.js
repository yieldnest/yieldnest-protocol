
const fs = require('fs');
const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));
    const depositPoolAddress = addresses.depositPool;

    const DepositPool = await hre.ethers.getContractFactory("DepositPool");
    const depositPool = DepositPool.attach(depositPoolAddress);

    const depositAmount = hre.ethers.utils.parseEther("0.0001");
    await depositPool.deposit(0, { value: depositAmount });

    console.log(`Deposited ${depositAmount} ETH to DepositPool at address ${depositPoolAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

