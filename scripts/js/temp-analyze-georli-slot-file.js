const fs = require('fs');
const path = require('path');

let rawdata = fs.readFileSync(path.resolve(__dirname, '/Users/dan/src/yieldnest/yieldnest-protocol/scripts/goerli_slot_6399998.json'));
let slotData = JSON.parse(rawdata).data;

console.log(Object.keys(slotData.slot));
for (let key in slotData.slot) {
    console.log(`${key}: ${JSON.stringify(slotData.slot[key])}`);
}



return;




let stateRootProofStruct = {
    beaconStateRoot: slotData.beaconStateRoot,
    stateRootProof: slotData.StateRootAgainstLatestBlockHeaderProof.slice(0, 3)
};

let validatorIndices = [slotData.validatorIndex];

let proofsArray = [];
for (let i = 0; i <= 45; i++) {
    if (slotData.WithdrawalCredentialProof[i]) {
        proofsArray.push(slotData.WithdrawalCredentialProof[i]);
    }
}

let validatorFieldsArray = [];
for (let i = 0; i <= 7; i++) {
    if (slotData.ValidatorFields[i]) {
        validatorFieldsArray.push(slotData.ValidatorFields[i]);
    }
}


console.log('stateRootProofStruct:', stateRootProofStruct);
console.log('validatorIndices:', validatorIndices);
console.log('proofsArray:', proofsArray);
console.log('validatorFieldsArray:', validatorFieldsArray);
