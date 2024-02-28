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
    }

    mapping(uint256 => Actors) public actors;

    constructor() {
        actors[1] = Actors({
            DEFAULT_SIGNER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PROXY_ADMIN_OWNER:		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            TRANSFER_ENABLED_EOA:	0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            ADMIN: 					0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            STAKING_ADMIN: 			0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            STAKING_NODES_ADMIN: 	0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            VALIDATOR_MANAGER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            FEE_RECEIVER: 			0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PAUSE_ADMIN:            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        });

        actors[5] = Actors({
            DEFAULT_SIGNER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PROXY_ADMIN_OWNER:		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            TRANSFER_ENABLED_EOA:	0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            ADMIN: 					0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            STAKING_ADMIN: 			0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            STAKING_NODES_ADMIN: 	0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            VALIDATOR_MANAGER: 		0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            FEE_RECEIVER: 			0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            PAUSE_ADMIN:            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

        });
    }

    function getActors(uint256 chainId) external view returns (Actors memory) {
        return actors[chainId];
    }
}


