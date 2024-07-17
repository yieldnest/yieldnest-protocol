// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
contract ActorAddresses {
    struct EOAActors {
        address DEFAULT_SIGNER;
        address DEPOSIT_BOOTSTRAPPER;
    }

    struct AdminActors {
        address ADMIN;
        address STAKING_ADMIN;
        address PROXY_ADMIN_OWNER;
        address REWARDS_ADMIN;
        address FEE_RECEIVER;
        address ORACLE_ADMIN;
        address STAKING_NODES_DELEGATOR;
        address UNPAUSE_ADMIN;
        address ASSET_MANAGER;
        address EIGEN_STRATEGY_ADMIN;
    }

    struct OpsActors {
        address STAKING_NODES_OPERATOR;
        address VALIDATOR_MANAGER;
        address LSD_RESTAKING_MANAGER;
        address STAKING_NODE_CREATOR;
        address POOLED_DEPOSITS_OWNER;
        address PAUSE_ADMIN;
        address REFERRAL_PUBLISHER;
        address STRATEGY_CONTROLLER;
        address TOKEN_STAKING_NODE_OPERATOR;
    }

    struct Wallets {
        address YNSecurityCouncil;
        address YNDelegator;
        address YNDev;
        address YNValidatorService;
        address YNStrategyController;
        address YNTokenStakingNodeOperator;
    }

    struct Actors {
        EOAActors eoa;
        AdminActors admin;
        OpsActors ops;
        Wallets wallets;
    }

    mapping(uint256 => Actors) public actors;

    constructor() {

        {
            Wallets memory holeskyWallets = Wallets({
                YNSecurityCouncil: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                YNDelegator: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                YNDev: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                YNValidatorService: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                // TODO: replace with concrete deployment
                YNStrategyController: 0x1234567890123456789012345678901234567890,
                // TODO: replace with concrete deployment
                YNTokenStakingNodeOperator:0x2234567890123456789012345678901234567890
            });

            actors[17000] = Actors({
                eoa: EOAActors({
                    DEFAULT_SIGNER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5,
                    DEPOSIT_BOOTSTRAPPER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5
                }),
                admin: AdminActors({
                    ADMIN: holeskyWallets.YNSecurityCouncil,
                    STAKING_ADMIN: holeskyWallets.YNSecurityCouncil,
                    PROXY_ADMIN_OWNER: holeskyWallets.YNSecurityCouncil,
                    REWARDS_ADMIN: holeskyWallets.YNSecurityCouncil,
                    FEE_RECEIVER: holeskyWallets.YNSecurityCouncil,
                    ORACLE_ADMIN: holeskyWallets.YNSecurityCouncil,
                    STAKING_NODES_DELEGATOR: holeskyWallets.YNDelegator,
                    UNPAUSE_ADMIN: holeskyWallets.YNSecurityCouncil,
                    ASSET_MANAGER: holeskyWallets.YNSecurityCouncil,
                    EIGEN_STRATEGY_ADMIN: holeskyWallets.YNSecurityCouncil
                }),
                ops: OpsActors({
                    STAKING_NODES_OPERATOR: holeskyWallets.YNDev,
                    VALIDATOR_MANAGER: holeskyWallets.YNValidatorService,
                    LSD_RESTAKING_MANAGER: holeskyWallets.YNDev,
                    STAKING_NODE_CREATOR: holeskyWallets.YNDev,
                    POOLED_DEPOSITS_OWNER: holeskyWallets.YNDev,
                    PAUSE_ADMIN: holeskyWallets.YNSecurityCouncil,
                    REFERRAL_PUBLISHER: holeskyWallets.YNDev,
                    STRATEGY_CONTROLLER: holeskyWallets.YNStrategyController,
                    TOKEN_STAKING_NODE_OPERATOR: holeskyWallets.YNTokenStakingNodeOperator
                }),
                wallets: holeskyWallets
            });
        }

        Wallets memory mainnetWallets = Wallets({
            YNSecurityCouncil: 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975,
            YNDelegator: 0xDF51B7843817F76220C0970eF58Ba726630028eF,
            YNDev: 0xa08F39d30dc865CC11a49b6e5cBd27630D6141C3,
            YNValidatorService: 0x8e20eAf121154B69B7b880FA6c617c0175c4dE2e,
            // TODO: replace with concrete deployment
            YNStrategyController: 0x1234567890123456789012345678901234567890,
            // TODO: replace with concrete deployment
            YNTokenStakingNodeOperator:0x2234567890123456789012345678901234567890
        });

        actors[1] = Actors({
            eoa: EOAActors({
                DEFAULT_SIGNER: 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D,
                DEPOSIT_BOOTSTRAPPER: 0x67a114e733b52CAC50A168F02b5626f500801C62
            }),
            admin: AdminActors({
                ADMIN: mainnetWallets.YNSecurityCouncil,
                STAKING_ADMIN: mainnetWallets.YNSecurityCouncil,
                PROXY_ADMIN_OWNER: mainnetWallets.YNSecurityCouncil,
                REWARDS_ADMIN: mainnetWallets.YNSecurityCouncil,
                FEE_RECEIVER: mainnetWallets.YNSecurityCouncil,
                ORACLE_ADMIN: mainnetWallets.YNSecurityCouncil,
                STAKING_NODES_DELEGATOR: mainnetWallets.YNDelegator,
                UNPAUSE_ADMIN: mainnetWallets.YNSecurityCouncil,
                ASSET_MANAGER: mainnetWallets.YNSecurityCouncil,
                EIGEN_STRATEGY_ADMIN: mainnetWallets.YNSecurityCouncil
            }),
            ops: OpsActors({
                STAKING_NODES_OPERATOR:mainnetWallets.YNDev,
                VALIDATOR_MANAGER: mainnetWallets.YNValidatorService,
                LSD_RESTAKING_MANAGER: mainnetWallets.YNDev,
                STAKING_NODE_CREATOR: mainnetWallets.YNDev,
                POOLED_DEPOSITS_OWNER: 0xE1fAc59031520FD1eb901da990Da12Af295e6731,
                PAUSE_ADMIN: mainnetWallets.YNDev,
                REFERRAL_PUBLISHER: mainnetWallets.YNDev,
                STRATEGY_CONTROLLER: mainnetWallets.YNStrategyController,
                TOKEN_STAKING_NODE_OPERATOR: mainnetWallets.YNTokenStakingNodeOperator
            }),
            wallets: mainnetWallets
        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}
