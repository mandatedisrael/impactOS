// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { SomniaVerificationAdapter } from "../src/SomniaVerificationAdapter.sol";
import { IImpactEscrow } from "../src/interfaces/IImpactEscrow.sol";
import { ISomniaAgents } from "../src/interfaces/ISomniaAgents.sol";
import { SomniaConfig } from "../src/libraries/SomniaConfig.sol";

contract DeployImpactOS is Script {
    error GuardianMustBeBroadcaster(address guardian, address broadcaster);

    function run() external returns (ImpactEscrow escrow, SomniaVerificationAdapter adapter) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(privateKey);
        address principalToken = vm.envAddress("PRINCIPAL_TOKEN_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address resolver = vm.envAddress("RESOLVER_ADDRESS");
        if (guardian != broadcaster) {
            revert GuardianMustBeBroadcaster(guardian, broadcaster);
        }

        ISomniaAgents platform = ISomniaAgents(SomniaConfig.agentsForChain(block.chainid));

        vm.startBroadcast(privateKey);
        escrow = new ImpactEscrow(IERC20(principalToken), guardian, resolver);
        adapter = new SomniaVerificationAdapter(IImpactEscrow(address(escrow)), platform, guardian);
        escrow.configureVerifierAdapter(address(adapter));
        vm.stopBroadcast();
    }
}
