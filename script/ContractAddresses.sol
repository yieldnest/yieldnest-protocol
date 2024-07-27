// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


contract ContractAddresses {

    struct YieldNestAddresses {
        address YNETH_ADDRESS;
        address STAKING_NODES_MANAGER_ADDRESS;
        address REWARDS_DISTRIBUTOR_ADDRESS;
        address EXECUTION_LAYER_RECEIVER_ADDRESS;
        address CONSENSUS_LAYER_RECEIVER_ADDRESS;  
    }

    struct EigenlayerAddresses {
        address EIGENPOD_MANAGER_ADDRESS;
        address DELEGATION_MANAGER_ADDRESS;
        address DELEGATION_PAUSER_ADDRESS;
        address STRATEGY_MANAGER_ADDRESS;
        address STRATEGY_MANAGER_PAUSER_ADDRESS;
        address DELAYED_WITHDRAWAL_ROUTER_ADDRESS;
    }

    struct LSDAddresses {
        address SFRXETH_ADDRESS;
        address RETH_ADDRESS;
        address STETH_ADDRESS;
        address WSTETH_ADDRESS;
        address OETH_ADDRESS;
        address WOETH_ADDRESS;
        address OETH_ZAPPER_ADDRESS;
        address SWELL_ADDRESS;
        address METH_ADDRESS;
        address CBETH_ADDRESS;
    }

    struct LSDStrategies {
        address RETH_STRATEGY_ADDRESS;
        address STETH_STRATEGY_ADDRESS;
        address OETH_STRATEGY_ADDRESS;
        address SFRXETH_STRATEGY_ADDRESS;
        address SWELL_STRATEGY_ADDRESS;
        address METH_STRATEGY_ADDRESS;
        address CBETH_STRATEGY_ADDRESS;
    }

    struct EthereumAddresses {
        address WETH_ADDRESS;
        address DEPOSIT_2_ADDRESS;
    }

    struct ChainAddresses {
        EthereumAddresses ethereum;
        EigenlayerAddresses eigenlayer;
        LSDAddresses lsd;
        LSDStrategies lsdStrategies;
        YieldNestAddresses yn;
    }

    struct ChainIds {
        uint256 mainnet;
        uint256 holeksy;
    }

    mapping(uint256 => ChainAddresses) public addresses;
    ChainIds public chainIds = ChainIds({
        mainnet: 1,
        holeksy: 17000
    });

    constructor() {
        addresses[chainIds.mainnet] = ChainAddresses({
            ethereum: EthereumAddresses({
                WETH_ADDRESS: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                DEPOSIT_2_ADDRESS: 0x00000000219ab540356cBB839Cbe05303d7705Fa
            }),
            eigenlayer: EigenlayerAddresses({
                EIGENPOD_MANAGER_ADDRESS: 0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338,
                DELEGATION_MANAGER_ADDRESS: 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A,
                DELEGATION_PAUSER_ADDRESS: 0x369e6F597e22EaB55fFb173C6d9cD234BD699111,
                STRATEGY_MANAGER_ADDRESS: 0x858646372CC42E1A627fcE94aa7A7033e7CF075A,
                STRATEGY_MANAGER_PAUSER_ADDRESS: 0xBE1685C81aA44FF9FB319dD389addd9374383e90,
                DELAYED_WITHDRAWAL_ROUTER_ADDRESS: 0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: 0xac3E018457B222d93114458476f3E3416Abbe38F,
                RETH_ADDRESS: 0xae78736Cd615f374D3085123A210448E74Fc6393,
                STETH_ADDRESS: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
                WSTETH_ADDRESS: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                OETH_ADDRESS: 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3,
                WOETH_ADDRESS: 0xDcEe70654261AF21C44c093C300eD3Bb97b78192,
                OETH_ZAPPER_ADDRESS: 0x9858e47BCbBe6fBAC040519B02d7cd4B2C470C66,
                SWELL_ADDRESS: 0xf951E335afb289353dc249e82926178EaC7DEd78,
                METH_ADDRESS: 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
                CBETH_ADDRESS: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
            }),
            lsdStrategies: LSDStrategies({
                RETH_STRATEGY_ADDRESS: 0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2,
                STETH_STRATEGY_ADDRESS: 0x93c4b944D05dfe6df7645A86cd2206016c51564D,
                OETH_STRATEGY_ADDRESS: 0xa4C637e0F704745D182e4D38cAb7E7485321d059,
                SFRXETH_STRATEGY_ADDRESS: 0x8CA7A5d6f3acd3A7A8bC468a8CD0FB14B6BD28b6,
                SWELL_STRATEGY_ADDRESS: 0x0Fe4F44beE93503346A3Ac9EE5A26b130a5796d6,
                METH_STRATEGY_ADDRESS: 0x298aFB19A105D59E74658C4C334Ff360BadE6dd2,
                CBETH_STRATEGY_ADDRESS: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
            }),
            yn: YieldNestAddresses({
                YNETH_ADDRESS: 0x09db87A538BD693E9d08544577d5cCfAA6373A48,
                STAKING_NODES_MANAGER_ADDRESS: 0x8C33A1d6d062dB7b51f79702355771d44359cD7d,
                REWARDS_DISTRIBUTOR_ADDRESS: 0x40d5FF3E218f54f4982661a0464a298Cf6652351,
                EXECUTION_LAYER_RECEIVER_ADDRESS: 0x1D6b2a11FFEa5F9a8Ed85A02581910b3d695C12b,
                CONSENSUS_LAYER_RECEIVER_ADDRESS: 0xE439fe4563F7666FCd7405BEC24aE7B0d226536e
            })
        });

        // In absence of Eigenlayer a placeholder address is used for all Eigenlayer addresses
        address placeholderAddress = address(1);

        addresses[chainIds.holeksy] = ChainAddresses({
            ethereum: EthereumAddresses({
                WETH_ADDRESS: placeholderAddress, // Placeholder address, replaced with address(1) for holesky
                DEPOSIT_2_ADDRESS: 0x4242424242424242424242424242424242424242
            }),
            eigenlayer: EigenlayerAddresses({
                EIGENPOD_MANAGER_ADDRESS: 0x30770d7E3e71112d7A6b7259542D1f680a70e315, // Placeholder address, replaced with address(1) for holesky
                DELEGATION_MANAGER_ADDRESS: 0xA44151489861Fe9e3055d95adC98FbD462B948e7, // Placeholder address, replaced with address(1) for holesky
                DELEGATION_PAUSER_ADDRESS: 0x28Ade60640fdBDb2609D8d8734D1b5cBeFc0C348, // Placeholder address, replaced with address(1) for holesky
                STRATEGY_MANAGER_ADDRESS: 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6, // Placeholder address, replaced with address(1) for holesky
                STRATEGY_MANAGER_PAUSER_ADDRESS: 0x28Ade60640fdBDb2609D8d8734D1b5cBeFc0C348,
                DELAYED_WITHDRAWAL_ROUTER_ADDRESS: 0x642c646053eaf2254f088e9019ACD73d9AE0FA32 // Placeholder address, replaced with address(1) for holesky
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3,
                RETH_ADDRESS: 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1, // source: https://docs.rocketpool.net/guides/staking/via-rp
                STETH_ADDRESS: 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034, // source: https://docs.lido.fi/deployed-contracts/holesky/
                WSTETH_ADDRESS: 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D, // source: https://docs.lido.fi/deployed-contracts/holesky/
                OETH_ADDRESS: 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3, // TODO: fix, placeholder until available
                WOETH_ADDRESS: 0xDcEe70654261AF21C44c093C300eD3Bb97b78192, // TODO: fix, placeholder until available
                OETH_ZAPPER_ADDRESS: 0x9858e47BCbBe6fBAC040519B02d7cd4B2C470C66, // TODO: fix, placeholder until available
                SWELL_ADDRESS: 0xf951E335afb289353dc249e82926178EaC7DEd78, // TODO: fix, placeholder until available
                METH_ADDRESS: 0xe3C063B1BEe9de02eb28352b55D49D85514C67FF,
                CBETH_ADDRESS: 0x8720095Fa5739Ab051799211B146a2EEE4Dd8B37
            }),
            lsdStrategies: LSDStrategies({
                RETH_STRATEGY_ADDRESS: 0x3A8fBdf9e77DFc25d09741f51d3E181b25d0c4E0,
                STETH_STRATEGY_ADDRESS: 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3,
                OETH_STRATEGY_ADDRESS: 0xa4C637e0F704745D182e4D38cAb7E7485321d059, // TODO: fix, placeholder until available
                SFRXETH_STRATEGY_ADDRESS: 0x9281ff96637710Cd9A5CAcce9c6FAD8C9F54631c,
                SWELL_STRATEGY_ADDRESS: 0x0Fe4F44beE93503346A3Ac9EE5A26b130a5796d6, // TODO: fix, placeholder until available
                METH_STRATEGY_ADDRESS: 0xaccc5A86732BE85b5012e8614AF237801636F8e5,
                CBETH_STRATEGY_ADDRESS: 0x70EB4D3c164a6B4A5f908D4FBb5a9cAfFb66bAB6
            }),
            yn: YieldNestAddresses({
                YNETH_ADDRESS: 0xd9029669BC74878BCB5BE58c259ed0A277C5c16E,
                STAKING_NODES_MANAGER_ADDRESS: 0xc2387EBb4Ea66627E3543a771e260Bd84218d6a1,
                REWARDS_DISTRIBUTOR_ADDRESS: 0x82915efF62af9FCC0d0735b8681959e069E3f2D8,
                EXECUTION_LAYER_RECEIVER_ADDRESS: 0xA5E9E1ceb4cC1854d0e186a9B3E67158b84AD072,
                CONSENSUS_LAYER_RECEIVER_ADDRESS: 0x706EED02702fFE9CBefD6A65E63f3C2b59B7eF2d
            })
        });
    }

    function getChainAddresses(uint256 chainId) external view returns (ChainAddresses memory) {
        return addresses[chainId];
    }
}
