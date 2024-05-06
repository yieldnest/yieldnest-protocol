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
    }

    struct OpsActors {
        address STAKING_NODES_OPERATOR;
        address VALIDATOR_MANAGER;
        address LSD_RESTAKING_MANAGER;
        address STAKING_NODE_CREATOR;
        address POOLED_DEPOSITS_OWNER;
        address PAUSE_ADMIN;
    }

    struct Wallets {
        address YNSecurityCouncil;
        address YNDelegator;
        address YNDev;
    }

    struct Actors {
        EOAActors eoa;
        AdminActors admin;
        OpsActors ops;
        Wallets wallets;
    }

    mapping(uint256 => Actors) public actors;

    constructor() {

        Wallets memory holeskyWallets = Wallets({
            YNSecurityCouncil: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
            YNDelegator: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
            YNDev: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39
        });

        actors[17000] = Actors({
            eoa: EOAActors({
                DEFAULT_SIGNER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5,
                DEPOSIT_BOOTSTRAPPER: 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5
            }),
            admin: AdminActors({
                ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                STAKING_ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                PROXY_ADMIN_OWNER: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                REWARDS_ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                FEE_RECEIVER: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                ORACLE_ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                STAKING_NODES_DELEGATOR: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                UNPAUSE_ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913
            }),
            ops: OpsActors({
                STAKING_NODES_OPERATOR: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                VALIDATOR_MANAGER: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                LSD_RESTAKING_MANAGER: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                STAKING_NODE_CREATOR: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                POOLED_DEPOSITS_OWNER: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39,
                PAUSE_ADMIN: 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39
            }),
            wallets: holeskyWallets
        });

        Wallets memory mainnetWallets = Wallets({
            YNSecurityCouncil: 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975,
            YNDelegator: 0xDF51B7843817F76220C0970eF58Ba726630028eF,
            YNDev: 0xa08F39d30dc865CC11a49b6e5cBd27630D6141C3
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
                UNPAUSE_ADMIN: mainnetWallets.YNSecurityCouncil
            }),
            ops: OpsActors({
                STAKING_NODES_OPERATOR:mainnetWallets.YNDev,
                VALIDATOR_MANAGER: mainnetWallets.YNDev,
                LSD_RESTAKING_MANAGER: mainnetWallets.YNDev,
                STAKING_NODE_CREATOR: mainnetWallets.YNDev,
                POOLED_DEPOSITS_OWNER: 0xE1fAc59031520FD1eb901da990Da12Af295e6731,
                PAUSE_ADMIN: mainnetWallets.YNDev
            }),
            wallets: mainnetWallets
        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}
