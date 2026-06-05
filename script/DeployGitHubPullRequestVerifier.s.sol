// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { GitHubPullRequestVerifier } from "../src/GitHubPullRequestVerifier.sol";
import { ISomniaAgents } from "../src/interfaces/ISomniaAgents.sol";
import { SomniaConfig } from "../src/libraries/SomniaConfig.sol";

contract DeployGitHubPullRequestVerifier is Script {
    function run() external returns (GitHubPullRequestVerifier verifier) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address administrator = vm.addr(privateKey);
        ISomniaAgents platform = ISomniaAgents(SomniaConfig.agentsForChain(block.chainid));

        vm.startBroadcast(privateKey);
        verifier = new GitHubPullRequestVerifier(platform, administrator);
        vm.stopBroadcast();
    }
}
