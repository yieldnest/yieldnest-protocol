const { ethers } = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

async function generateValidatorBalanceProof(validatorAddress) {
  const beaconOracle = await ethers.getContract("EigenLayerBeaconOracle");
  const blockRoot = await beaconOracle.getBeaconBlockRoot();

  // Assuming the balances are stored in a mapping with validator address as key
  const balance = await beaconOracle.balances(validatorAddress);

  // Generate the merkle tree
  const leaves = [ethers.utils.hexlify(keccak256(validatorAddress)), balance];
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });

  // Generate the merkle proof
  const proof = tree.getHexProof(ethers.utils.hexlify(keccak256(validatorAddress)));

  return { blockRoot, proof };
}

