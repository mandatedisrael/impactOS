// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library SomniaConfig {
    uint256 internal constant MAINNET_CHAIN_ID = 5031;
    uint256 internal constant SHANNON_CHAIN_ID = 50312;

    address internal constant MAINNET_AGENTS = 0x5E5205CF39E766118C01636bED000A54D93163E6;
    address internal constant SHANNON_AGENTS = 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776;

    uint256 internal constant JSON_API_AGENT_ID = 13_174_292_974_160_097_713;
    uint256 internal constant DEFAULT_SUBCOMMITTEE_SIZE = 3;

    // Somnia currently asks for this reward per elected JSON API runner.
    // The platform's operations reserve is queried separately at runtime.
    uint256 internal constant JSON_API_PRICE_PER_AGENT = 0.03 ether;

    error UnsupportedChain(uint256 chainId);

    function agentsForChain(uint256 chainId) internal pure returns (address) {
        if (chainId == MAINNET_CHAIN_ID) return MAINNET_AGENTS;
        if (chainId == SHANNON_CHAIN_ID) return SHANNON_AGENTS;
        revert UnsupportedChain(chainId);
    }

    function practicalJsonRequestDeposit(uint256 operationsReserve)
        internal
        pure
        returns (uint256)
    {
        return operationsReserve + (JSON_API_PRICE_PER_AGENT * DEFAULT_SUBCOMMITTEE_SIZE);
    }
}
