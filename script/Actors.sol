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

    struct Actors {
        EOAActors eoa;
        AdminActors admin;
        OpsActors ops;
    }

    mapping(uint256 => Actors) public actors;

    constructor() {
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
            })
        });


        actors[1] = Actors({
            eoa: EOAActors({
                DEFAULT_SIGNER: 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D,
                DEPOSIT_BOOTSTRAPPER: 0x67a114e733b52CAC50A168F02b5626f500801C62
            }),
            admin: AdminActors({
                ADMIN: 0x90F79bf6EB2c4f870365E785982E1f101E93b906,
                STAKING_ADMIN: 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
                PROXY_ADMIN_OWNER: 0xE1fAc59031520FD1eb901da990Da12Af295e6731,
                REWARDS_ADMIN: 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913,
                FEE_RECEIVER: 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
                ORACLE_ADMIN: 0x71bE63f3384f5fb98995898A86B02Fb2426c5788,
                STAKING_NODES_DELEGATOR: 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec,
                UNPAUSE_ADMIN: 0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097
            }),
            ops: OpsActors({
                STAKING_NODES_OPERATOR: 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
                VALIDATOR_MANAGER: 0x976EA74026E726554dB657fA54763abd0C3a0aa9,
                LSD_RESTAKING_MANAGER: 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720,
                STAKING_NODE_CREATOR: 0xBcd4042DE499D14e55001CcbB24a551F3b954096,
                POOLED_DEPOSITS_OWNER: 0xE1fAc59031520FD1eb901da990Da12Af295e6731,
                PAUSE_ADMIN: 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
            })
        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}
