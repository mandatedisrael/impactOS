// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { GitHubPullRequestVerifier } from "../src/GitHubPullRequestVerifier.sol";

contract RequestGitHubVerification is Script {
    error FundingTransferFailed(uint256 amount);

    function run() external returns (uint256 requestId) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        GitHubPullRequestVerifier verifier =
            GitHubPullRequestVerifier(payable(vm.envAddress("VERIFIER_ADDRESS")));
        string memory repositoryOwner = vm.envString("GITHUB_OWNER");
        string memory repositoryName = vm.envString("GITHUB_REPO");
        uint256 pullRequestNumber = vm.envUint("GITHUB_PR_NUMBER");

        uint256 deposit = verifier.quoteRequestDeposit();
        uint256 missingBalance =
            address(verifier).balance < deposit ? deposit - address(verifier).balance : 0;

        vm.startBroadcast(privateKey);
        if (missingBalance != 0) {
            (bool funded,) = payable(address(verifier)).call{ value: missingBalance }("");
            if (!funded) revert FundingTransferFailed(missingBalance);
        }
        requestId = verifier.requestMergedStatus(repositoryOwner, repositoryName, pullRequestNumber);
        vm.stopBroadcast();
    }
}
