// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
contract ActorAddresses {
    struct EOAActors {
        address DEFAULT_SIGNER;
        address DEPOSIT_BOOTSTRAPPER;
        address MOCK_CONTROLLER;
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
        address STAKING_NODE_CREATOR;
        address POOLED_DEPOSITS_OWNER;
        address PAUSE_ADMIN;
        address REFERRAL_PUBLISHER;
        address WITHDRAWAL_MANAGER;
        address REDEMPTION_ASSET_WITHDRAWER;
        address REQUEST_FINALIZER;
        address STAKING_NODES_WITHDRAWER;
        address STRATEGY_CONTROLLER;
        address TOKEN_STAKING_NODE_OPERATOR;
        address TOKEN_STAKING_NODES_WITHDRAWER;
        address YNEIGEN_REQUEST_FINALIZER;
        address YNEIGEN_WITHDRAWAL_MANAGER;
    }

    struct Wallets {
        address YNSecurityCouncil;
        address YNDelegator;
        address YNDev;
        address YNValidatorService;
        address YNStrategyController;
        address YNTokenStakingNodeOperator;
        address YNWithdrawalsETH;
        address YnOperator;
        address YNnWithdrawalsYnEigen;
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
                YNStrategyController: 0x447F34933D3Eeac79a8E22352BaC976A1701aee0,
                // TODO: replace with concrete deployment
                YNTokenStakingNodeOperator: 0x2234567890123456789012345678901234567890,
                YNWithdrawalsETH: 0x0e36E2bCD71059E02822DFE52cBa900730b07c07,
                YnOperator: 0x530F6057e93b54Ec39D6472DA75712db2178780C,
                YNnWithdrawalsYnEigen: 0x0e36E2bCD71059E02822DFE52cBa900730b07c07
            });
            actors[17000] = Actors({
                eoa: EOAActors({
                    DEFAULT_SIGNER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5,
                    DEPOSIT_BOOTSTRAPPER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5,
                    MOCK_CONTROLLER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5
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
                    STAKING_NODES_OPERATOR: holeskyWallets.YnOperator,
                    VALIDATOR_MANAGER: holeskyWallets.YNValidatorService,
                    STAKING_NODE_CREATOR: holeskyWallets.YNDev,
                    POOLED_DEPOSITS_OWNER: holeskyWallets.YNDev,
                    PAUSE_ADMIN: holeskyWallets.YNSecurityCouncil,
                    REFERRAL_PUBLISHER: holeskyWallets.YNDev,
                    STRATEGY_CONTROLLER: holeskyWallets.YNStrategyController,
                    TOKEN_STAKING_NODE_OPERATOR: holeskyWallets.YNTokenStakingNodeOperator,
                    WITHDRAWAL_MANAGER: holeskyWallets.YNWithdrawalsETH,
                    REDEMPTION_ASSET_WITHDRAWER: holeskyWallets.YNDev,
                    REQUEST_FINALIZER: holeskyWallets.YNWithdrawalsETH,
                    STAKING_NODES_WITHDRAWER: holeskyWallets.YNWithdrawalsETH,
                    TOKEN_STAKING_NODES_WITHDRAWER: holeskyWallets.YNnWithdrawalsYnEigen,
                    YNEIGEN_REQUEST_FINALIZER: holeskyWallets.YNnWithdrawalsYnEigen,
                    YNEIGEN_WITHDRAWAL_MANAGER: holeskyWallets.YNnWithdrawalsYnEigen
                }),
                wallets: holeskyWallets
            });
        }

        Wallets memory mainnetWallets = Wallets({
            YNSecurityCouncil: 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975,
            YNDelegator: 0xDF51B7843817F76220C0970eF58Ba726630028eF,
            YNDev: 0xa08F39d30dc865CC11a49b6e5cBd27630D6141C3,
            YNValidatorService: 0x8e20eAf121154B69B7b880FA6c617c0175c4dE2e,
            YNStrategyController: 0x0573A7DaFBc080064663623979287286Bb65C1BD,
            // TODO: replace with concrete deployment
            YNTokenStakingNodeOperator: 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975, // same as YNSecurityCouncil
            YNWithdrawalsETH: 0x7f7187fbD6e508bC23268746dff535cfC8EbC87b,
            YnOperator: 0x591A163AcfDb6F79674b08e5F069b4905a230ddD,
            YNnWithdrawalsYnEigen: 0x15519e68Ca7544d1C919A2A6e9065375A1f0C80A
        });

        actors[1] = Actors({
            eoa: EOAActors({
                DEFAULT_SIGNER: 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D,
                DEPOSIT_BOOTSTRAPPER: 0x67a114e733b52CAC50A168F02b5626f500801C62,
                MOCK_CONTROLLER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5
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
                STAKING_NODES_OPERATOR:mainnetWallets.YnOperator,
                VALIDATOR_MANAGER: mainnetWallets.YNValidatorService,
                STAKING_NODE_CREATOR: mainnetWallets.YNDev,
                POOLED_DEPOSITS_OWNER: 0xE1fAc59031520FD1eb901da990Da12Af295e6731,
                PAUSE_ADMIN: mainnetWallets.YNDev,
                REFERRAL_PUBLISHER: mainnetWallets.YNDev,
                STRATEGY_CONTROLLER: mainnetWallets.YNStrategyController,
                TOKEN_STAKING_NODE_OPERATOR: mainnetWallets.YNTokenStakingNodeOperator,
                WITHDRAWAL_MANAGER: mainnetWallets.YNWithdrawalsETH,
                REDEMPTION_ASSET_WITHDRAWER: mainnetWallets.YNDev,
                REQUEST_FINALIZER: mainnetWallets.YNWithdrawalsETH,
                STAKING_NODES_WITHDRAWER: mainnetWallets.YNWithdrawalsETH,
                TOKEN_STAKING_NODES_WITHDRAWER: mainnetWallets.YNnWithdrawalsYnEigen,
                YNEIGEN_REQUEST_FINALIZER: mainnetWallets.YNnWithdrawalsYnEigen,
                YNEIGEN_WITHDRAWAL_MANAGER: mainnetWallets.YNnWithdrawalsYnEigen
            }),
            wallets: mainnetWallets
        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}
