
const { registerValidators } = require('./registerValidators');


async function runInterval(fn, interval, waitOnError) {
    while (true) {
        try {
            await fn();
            await new Promise(resolve => setTimeout(resolve, interval));
        } catch (error) {
            console.error(error);
            await new Promise(resolve => setTimeout(resolve, interval + waitOnError));
        }
    }
}

async function checkAndRegisterValidators(ynETHContract) {
    const balance = 
        await hre.ethers.provider.getBalance(ynETHContract.address);

    console.log(`Balance of ynETH: ${balance}`);
    const minBalance = hre.ethers.utils.parseEther('32');
    if (balance >= minBalance) {

        console.log('Balance is sufficient for registration');

        const initialBalance = await ynETHContract.totalDepositedInValidators();
        await registerValidators();
        const finalBalance = await ynETHContract.totalDepositedInValidators();
        const expectedFinalBalance = initialBalance.add(minBalance);
        assert(finalBalance.eq(expectedFinalBalance), 'Final balance did not increase by exactly minBalance');
    } else {
        console.log('The balance is not yet 32 ETH');
    }
}


async function main() {

    const ynETHAddress = require('../goerli-addresses.json').ynETH;
    const ynETHContract = await ethers.getContractAt('ynETH', ynETHAddress);

    console.log('Registering balance check..');
    await  runInterval(() => checkAndRegisterValidators(ynETHContract), 5000, 1000);
    
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
}
