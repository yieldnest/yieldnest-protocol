const { deploy } = require('./deploy');
const { retryVerify } = require('./utils');

async function main() {
    const fs = require('fs');
    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json', 'utf8'));
    const ynETH = addresses.ynETH;
    const oracle = addresses.oracle;
    const stakingNodesManager = addresses.stakingNodesManager;

    const ynViewerContract = await hre.ethers.getContractFactory('ynViewer');
    const ynViewer = await ynViewerContract.deploy(ynETH, stakingNodesManager, oracle);

    console.log("ynViewer deployed to:", ynViewer.address);

    fs.writeFileSync('goerli-addresses.json', JSON.stringify({... addresses, ynViewer: ynViewer.address }), null, 2);

    await retryVerify('ynViewer', ynViewer.address, [ynETH, stakingNodesManager, oracle]);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
