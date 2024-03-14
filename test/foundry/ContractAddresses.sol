// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

contract ContractAddresses {

    struct EigenlayerAddresses {
        address EIGENPOD_MANAGER_ADDRESS;
        address DELEGATION_MANAGER_ADDRESS;
        address DELEGATION_PAUSER_ADDRESS;
        address STRATEGY_MANAGER_ADDRESS;
        address DELAYED_WITHDRAWAL_ROUTER_ADDRESS;
    }

    struct LSDAddresses {
        address SFRXETH_ADDRESS;
        address RETH_ADDRESS;
        address STETH_ADDRESS;
        address RETH_FEED_ADDRESS;
        address STETH_FEED_ADDRESS;
        address RETH_STRATEGY_ADDRESS;
        address STETH_STRATEGY_ADDRESS;
    }

    struct EthereumAddresses {
        address WETH_ADDRESS;
        address DEPOSIT_2_ADDRESS;
    }

    struct ChainAddresses {
        EthereumAddresses ethereum;
        EigenlayerAddresses eigenlayer;
        LSDAddresses lsd;
    }

    mapping(uint256 => ChainAddresses) public addresses;

    constructor() {
        addresses[1] = ChainAddresses({
            ethereum: EthereumAddresses({
                WETH_ADDRESS: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                DEPOSIT_2_ADDRESS: 0x00000000219ab540356cBB839Cbe05303d7705Fa
            }),
            eigenlayer: EigenlayerAddresses({
                EIGENPOD_MANAGER_ADDRESS: 0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338,
                DELEGATION_MANAGER_ADDRESS: 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A,
                DELEGATION_PAUSER_ADDRESS: 0x369e6F597e22EaB55fFb173C6d9cD234BD699111,
                STRATEGY_MANAGER_ADDRESS: 0x858646372CC42E1A627fcE94aa7A7033e7CF075A,
                DELAYED_WITHDRAWAL_ROUTER_ADDRESS: 0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: 0xac3E018457B222d93114458476f3E3416Abbe38F,
                RETH_ADDRESS: 0xae78736Cd615f374D3085123A210448E74Fc6393,
                STETH_ADDRESS: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
                RETH_FEED_ADDRESS: 0x536218f9E9Eb48863970252233c8F271f554C2d0,
                STETH_FEED_ADDRESS: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812,
                RETH_STRATEGY_ADDRESS: 0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2,
                STETH_STRATEGY_ADDRESS: 0x93c4b944D05dfe6df7645A86cd2206016c51564D
            })
        });

        addresses[5] = ChainAddresses({
            ethereum: EthereumAddresses({
                WETH_ADDRESS: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
                DEPOSIT_2_ADDRESS: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
            }),
            eigenlayer: EigenlayerAddresses({
                EIGENPOD_MANAGER_ADDRESS: 0xa286b84C96aF280a49Fe1F40B9627C2A2827df41,
                DELEGATION_MANAGER_ADDRESS: 0x1b7b8F6b258f95Cf9596EabB9aa18B62940Eb0a8,
                DELEGATION_PAUSER_ADDRESS: 0x369e6F597e22EaB55fFb173C6d9cD234BD699111,
                STRATEGY_MANAGER_ADDRESS: 0x779d1b5315df083e3F9E94cB495983500bA8E907,
                DELAYED_WITHDRAWAL_ROUTER_ADDRESS: 0x89581561f1F98584F88b0d57c2180fb89225388f
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: 0x0000000000000000000000000000000000000000,
                RETH_ADDRESS: 0x178E141a0E3b34152f73Ff610437A7bf9B83267A,
                STETH_ADDRESS: 0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F,
                RETH_FEED_ADDRESS: 0x9c18A124aB957578BE5AE04088159E4AAb22fAc3,
                STETH_FEED_ADDRESS: 0x9c18A124aB957578BE5AE04088159E4AAb22fAc3,
                RETH_STRATEGY_ADDRESS: 0x879944A8cB437a5f8061361f82A6d4EED59070b5,
                STETH_STRATEGY_ADDRESS: 0xB613E78E2068d7489bb66419fB1cfa11275d14da
            })
        });

        // In absence of Eigenlayer a placeholder address is used for all Eigenlayer addresses
        address placeholderAddress = address(1);

        addresses[17000] = ChainAddresses({
            ethereum: EthereumAddresses({
                WETH_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                DEPOSIT_2_ADDRESS: 0x4242424242424242424242424242424242424242
            }),
            eigenlayer: EigenlayerAddresses({
                EIGENPOD_MANAGER_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                DELEGATION_MANAGER_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                DELEGATION_PAUSER_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                STRATEGY_MANAGER_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                DELAYED_WITHDRAWAL_ROUTER_ADDRESS: placeholderAddress // Placeholder address, replaced with address(1) for holesky
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                RETH_ADDRESS: 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1, // source: https://docs.rocketpool.net/guides/staking/via-rp
                STETH_ADDRESS: 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034, // source: https://docs.lido.fi/deployed-contracts/holesky/
                RETH_FEED_ADDRESS: 0xe1e444A5Df450E7640323a21073bF01E0af054fA, // Self-created aggregator
                STETH_FEED_ADDRESS: 0xe1e444A5Df450E7640323a21073bF01E0af054fA, // Self-created aggregator
                RETH_STRATEGY_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                STETH_STRATEGY_ADDRESS: placeholderAddress // Placeholder address, replaced with address(1) for holesky
            })
        });
    }

    function getChainAddresses(uint256 chainId) external view returns (ChainAddresses memory) {
        return addresses[chainId];
    }

}
