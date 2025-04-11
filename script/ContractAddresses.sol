// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


contract ContractAddresses {

    struct YnEigenAddresses {
        address YNEIGEN_ADDRESS;
        address TOKEN_STAKING_NODES_MANAGER_ADDRESS;
        address ASSET_REGISTRY_ADDRESS;
        address EIGEN_STRATEGY_MANAGER_ADDRESS;
        address LSD_RATE_PROVIDER_ADDRESS;
        address YNEIGEN_DEPOSIT_ADAPTER_ADDRESS;
        address TIMELOCK_CONTROLLER_ADDRESS;
        address REDEMPTION_ASSETS_VAULT_ADDRESS;
        address WITHDRAWAL_QUEUE_MANAGER_ADDRESS;
        address WRAPPER;
        address WITHDRAWALS_PROCESSOR_ADDRESS;
    }

    struct YieldNestAddresses {
        address YNETH_ADDRESS;
        address STAKING_NODES_MANAGER_ADDRESS;
        address REWARDS_DISTRIBUTOR_ADDRESS;
        address EXECUTION_LAYER_RECEIVER_ADDRESS;
        address CONSENSUS_LAYER_RECEIVER_ADDRESS;  
        address YNETH_REDEMPTION_ASSETS_VAULT_ADDRESS;
        address WITHDRAWAL_QUEUE_MANAGER_ADDRESS;
        address WITHDRAWALS_PROCESSOR_ADDRESS;
    }

    struct EigenlayerAddresses {
        address EIGENPOD_MANAGER_ADDRESS;
        address DELEGATION_MANAGER_ADDRESS;
        address DELEGATION_PAUSER_ADDRESS;
        address STRATEGY_MANAGER_ADDRESS;
        address STRATEGY_MANAGER_PAUSER_ADDRESS;
        address REWARDS_COORDINATOR_ADDRESS;
        address ALLOCATION_MANAGER_ADDRESS;
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
        YnEigenAddresses ynEigen;
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
                DELEGATION_PAUSER_ADDRESS: 0x369e6F597e22EaB55fFb173C6d9cD234BD699111, // TODO: remove this if unused
                STRATEGY_MANAGER_ADDRESS: 0x858646372CC42E1A627fcE94aa7A7033e7CF075A,
                STRATEGY_MANAGER_PAUSER_ADDRESS: 0xBE1685C81aA44FF9FB319dD389addd9374383e90,
                REWARDS_COORDINATOR_ADDRESS: 0x7750d328b314EfFa365A0402CcfD489B80B0adda,
                ALLOCATION_MANAGER_ADDRESS: 0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39 
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
                CBETH_STRATEGY_ADDRESS: 0x54945180dB7943c0ed0FEE7EdaB2Bd24620256bc
            }),
            yn: YieldNestAddresses({
                YNETH_ADDRESS: 0x09db87A538BD693E9d08544577d5cCfAA6373A48,
                STAKING_NODES_MANAGER_ADDRESS: 0x8C33A1d6d062dB7b51f79702355771d44359cD7d,
                REWARDS_DISTRIBUTOR_ADDRESS: 0x40d5FF3E218f54f4982661a0464a298Cf6652351,
                EXECUTION_LAYER_RECEIVER_ADDRESS: 0x1D6b2a11FFEa5F9a8Ed85A02581910b3d695C12b,
                CONSENSUS_LAYER_RECEIVER_ADDRESS: 0xE439fe4563F7666FCd7405BEC24aE7B0d226536e,
                YNETH_REDEMPTION_ASSETS_VAULT_ADDRESS: 0x5D6e53c42E3B37f82F693937BC508940769c5caf,
                WITHDRAWAL_QUEUE_MANAGER_ADDRESS: 0x0BC9BC81aD379810B36AD5cC95387112990AA67b,
                WITHDRAWALS_PROCESSOR_ADDRESS: 0x6d052CdEd3F64aea51f6051F33b68b42016C5FbA
            }),
            ynEigen: YnEigenAddresses({
                YNEIGEN_ADDRESS: 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c,
                TOKEN_STAKING_NODES_MANAGER_ADDRESS: 0x6B566CB6cDdf7d140C59F84594756a151030a0C3,
                ASSET_REGISTRY_ADDRESS: 0x323C933df2523D5b0C756210446eeE0fB84270fd,
                EIGEN_STRATEGY_MANAGER_ADDRESS: 0x92D904019A92B0Cafce3492Abb95577C285A68fC,
                LSD_RATE_PROVIDER_ADDRESS: 0xb658Cf6F4C232Be5c6035f2b42b96393089F20D9,
                YNEIGEN_DEPOSIT_ADAPTER_ADDRESS: 0x9e72155d301a6555dc565315be72D295c76753c0,
                TIMELOCK_CONTROLLER_ADDRESS: 0xbB73f8a5B0074b27c6df026c77fA08B0111D017A,
                REDEMPTION_ASSETS_VAULT_ADDRESS: 0x73bC33999C34a5126CA19dC900F22690C288D55e,
                WITHDRAWAL_QUEUE_MANAGER_ADDRESS: 0x8Face3283E20b19d98a7a132274B69C1304D60b4,
                WRAPPER: 0x99dB7619C018D61dBC2822767B63240d311d6992,
                WITHDRAWALS_PROCESSOR_ADDRESS: 0x57F6991f1205Ba50D0Acc30aF08555721Dc4A117
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
                REWARDS_COORDINATOR_ADDRESS: 0xAcc1fb458a1317E886dB376Fc8141540537E68fE,
                ALLOCATION_MANAGER_ADDRESS: 0x78469728304326CBc65f8f95FA756B0B73164462
            }),
            lsd: LSDAddresses({
                SFRXETH_ADDRESS: 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3,
                RETH_ADDRESS: 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1, // source: https://docs.rocketpool.net/guides/staking/via-rp
                STETH_ADDRESS: 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034, // source: https://docs.lido.fi/deployed-contracts/holesky/
                WSTETH_ADDRESS: 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D, // source: https://docs.lido.fi/deployed-contracts/holesky/
                OETH_ADDRESS: 0x10B83FBce870642ee33f0877ffB7EA43530E473D, // TODO: fix, currently a YieldNest Mock is used
                WOETH_ADDRESS: 0xbaAcDcC565006b6429F57bC0f436dFAf14A526b1, // TODO: fix, currently a YieldNest Mock is used
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
                CONSENSUS_LAYER_RECEIVER_ADDRESS: 0x706EED02702fFE9CBefD6A65E63f3C2b59B7eF2d,
                YNETH_REDEMPTION_ASSETS_VAULT_ADDRESS: 0x3a2DD2f0f5A20768110a52fC4f091AB9d8631b58,
                WITHDRAWAL_QUEUE_MANAGER_ADDRESS: 0x141aAb320857145fB42240C979b800f48CE5B678,
                WITHDRAWALS_PROCESSOR_ADDRESS: 0x48E3FdCE3E2d5A3Fa34bdEd9eb9dEeBB48217ba3
            }),
            ynEigen: YnEigenAddresses({
                YNEIGEN_ADDRESS: 0x071bdC8eDcdD66730f45a3D3A6F794FAA37C75ED,
                TOKEN_STAKING_NODES_MANAGER_ADDRESS: 0x5c20D1a85C7d9acB503135a498E26Eb55d806552,
                ASSET_REGISTRY_ADDRESS: 0xaD31546AdbfE1EcD7137310508f112039a35b6F7,
                EIGEN_STRATEGY_MANAGER_ADDRESS: 0xA0a11A9b84bf87c0323bc183715a22eC7881B7FC,
                LSD_RATE_PROVIDER_ADDRESS: 0xd68C29263F6dC2Ff8D9307b3AfAcD6D6fDeFbB3A,
                YNEIGEN_DEPOSIT_ADAPTER_ADDRESS: 0x7d0c1F604571a1c015684e6c15f2DdEc432C5e74,
                TIMELOCK_CONTROLLER_ADDRESS: 0x62173555C27C67644C5634e114e42A63A59CD7A5,
                REDEMPTION_ASSETS_VAULT_ADDRESS: 0xd536087701fFf805d20ee6651E55C90D645fD1a3,
                WITHDRAWAL_QUEUE_MANAGER_ADDRESS: 0xaF8052DC454318D52A4478a91aCa14305590389f,
                WRAPPER: 0x8F61bcb28C5b88e5F10ec5bb3C18f231D763A309,
                WITHDRAWALS_PROCESSOR_ADDRESS: address(0) // TODO: This address is missing from the deployments file at deployments/YnLSDe-17000.json.
            })
        });
    }

    function getChainAddresses(uint256 chainId) external view returns (ChainAddresses memory) {
        return addresses[chainId];
    }

    function getChainIds() external view returns (ChainIds memory) {
        return chainIds;
    }

    function isSupportedChainId(uint256 chainId) external view returns (bool) {
        return chainId == chainIds.mainnet || chainId == chainIds.holeksy;
    }
}
