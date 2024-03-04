// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

contract ActorAddresses {

    struct Actors {
        address DEFAULT_SIGNER;
        address PROXY_ADMIN_OWNER;
        address TRANSFER_ENABLED_EOA;
        address ADMIN;
        address STAKING_ADMIN;
        address STAKING_NODES_ADMIN;
        address VALIDATOR_MANAGER;
        address FEE_RECEIVER;
        address PAUSE_ADMIN;
        address LSD_RESTAKING_MANAGER;
        address STAKING_NODE_CREATOR;
        address ORACLE_MANAGER;
    }

    mapping(uint256 => Actors) public actors;

    constructor() {
        actors[1] = Actors({
            DEFAULT_SIGNER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PROXY_ADMIN_OWNER:		0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            TRANSFER_ENABLED_EOA:	0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            ADMIN: 					0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            STAKING_ADMIN: 			0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
            STAKING_NODES_ADMIN: 	0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
            VALIDATOR_MANAGER: 		0x976EA74026E726554dB657fA54763abd0C3a0aa9,
            FEE_RECEIVER: 			0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
            PAUSE_ADMIN:            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
            LSD_RESTAKING_MANAGER:  0xa0Ee7A142d267C1f36714E4a8F75612F20a79720,
            STAKING_NODE_CREATOR: 0xBcd4042DE499D14e55001CcbB24a551F3b954096,
            ORACLE_MANAGER: 0x71bE63f3384f5fb98995898A86B02Fb2426c5788 // TODO: put the next addres here
        });

        actors[5] = Actors({
            DEFAULT_SIGNER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PROXY_ADMIN_OWNER:		0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            TRANSFER_ENABLED_EOA:	0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            ADMIN: 					0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            STAKING_ADMIN: 			0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
            STAKING_NODES_ADMIN: 	0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
            VALIDATOR_MANAGER: 		0x976EA74026E726554dB657fA54763abd0C3a0aa9,
            FEE_RECEIVER: 			0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
            PAUSE_ADMIN:            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
            LSD_RESTAKING_MANAGER:  0xa0Ee7A142d267C1f36714E4a8F75612F20a79720,
            STAKING_NODE_CREATOR: 0xBcd4042DE499D14e55001CcbB24a551F3b954096,
            ORACLE_MANAGER: 0x71bE63f3384f5fb98995898A86B02Fb2426c5788 // TODO: put the next addres here
        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}

