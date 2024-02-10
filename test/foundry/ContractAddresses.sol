contract ContractAddresses {
    struct ChainAddresses {
        address WETH_ADDRESS;
        address DEPOSIT_2_ADDRESS;
        address EIGENLAYER_EIGENPOD_MANAGER_ADDRESS;
        address EIGENLAYER_DELEGATION_MANAGER_ADDRESS;
        address EIGENLAYER_STRATEGY_MANAGER_ADDRESS;
    }

    mapping(uint256 => ChainAddresses) public addresses;

    constructor() {
        addresses[1] = ChainAddresses({
            WETH_ADDRESS: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            DEPOSIT_2_ADDRESS: 0x00000000219ab540356cBB839Cbe05303d7705Fa,
            EIGENLAYER_EIGENPOD_MANAGER_ADDRESS: 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A,
            EIGENLAYER_DELEGATION_MANAGER_ADDRESS: 0xa286b84C96aF280a49Fe1F40B9627C2A2827df41,
            EIGENLAYER_STRATEGY_MANAGER_ADDRESS: 0x858646372CC42E1A627fcE94aa7A7033e7CF075A
        });

        addresses[5] = ChainAddresses({
            WETH_ADDRESS: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
            DEPOSIT_2_ADDRESS: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b,
            EIGENLAYER_EIGENPOD_MANAGER_ADDRESS: 0xa286b84C96aF280a49Fe1F40B9627C2A2827df41,
            EIGENLAYER_DELEGATION_MANAGER_ADDRESS: 0x1b7b8F6b258f95Cf9596EabB9aa18B62940Eb0a8,
            EIGENLAYER_STRATEGY_MANAGER_ADDRESS: 0x779d1b5315df083e3F9E94cB495983500bA8E907
        });
    }

    function getChainAddresses(uint256 chainId) external view returns (ChainAddresses memory) {
        return addresses[chainId];
    }

}
