// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { GitHubPullRequestVerifier } from "../src/GitHubPullRequestVerifier.sol";
import { IJsonApiAgent } from "../src/interfaces/IJsonApiAgent.sol";
import { ISomniaAgents } from "../src/interfaces/ISomniaAgents.sol";
import { SomniaConfig } from "../src/libraries/SomniaConfig.sol";
import { MockSomniaAgents } from "./mocks/MockSomniaAgents.sol";

contract GitHubPullRequestVerifierRequestTest is Test {
    MockSomniaAgents private agents;
    GitHubPullRequestVerifier private verifier;

    address private constant ATTACKER = address(0xBEEF);

    function setUp() public {
        agents = new MockSomniaAgents();
        verifier = new GitHubPullRequestVerifier(ISomniaAgents(address(agents)), address(this));
        vm.deal(address(verifier), 1 ether);
    }

    function testQuotesOperationsReservePlusThreeAgentRewards() public view {
        assertEq(verifier.quoteRequestDeposit(), 0.12 ether);
    }

    function testAdministratorCreatesGitHubMergedRequest() public {
        vm.warp(1_750_000_000);

        uint256 requestId = verifier.requestMergedStatus("mandatedisrael", "impactOS", 42);

        assertEq(requestId, 1);
        assertEq(agents.lastAgentId(), SomniaConfig.JSON_API_AGENT_ID);
        assertEq(agents.lastRequester(), address(verifier));
        assertEq(agents.lastCallbackAddress(), address(verifier));
        assertEq(agents.lastCallbackSelector(), GitHubPullRequestVerifier.handleResponse.selector);
        assertEq(agents.lastValue(), 0.12 ether);
        assertEq(
            agents.lastPayload(),
            abi.encodeWithSelector(
                IJsonApiAgent.fetchBool.selector,
                "https://api.github.com/repos/mandatedisrael/impactOS/pulls/42",
                "merged"
            )
        );

        GitHubPullRequestVerifier.Verification memory verification =
            verifier.getVerification(requestId);
        assertEq(verification.repositoryOwner, "mandatedisrael");
        assertEq(verification.repositoryName, "impactOS");
        assertEq(verification.pullRequestNumber, 42);
        assertEq(
            uint256(verification.status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.Pending)
        );
        assertEq(verification.requestedAt, 1_750_000_000);
        assertEq(verification.resolvedAt, 0);
    }

    function testRejectsNonAdministrator() public {
        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(GitHubPullRequestVerifier.OnlyAdministrator.selector, ATTACKER)
        );
        verifier.requestMergedStatus("mandatedisrael", "impactOS", 42);
    }

    function testRejectsInvalidRepositoryInput() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                GitHubPullRequestVerifier.InvalidRepositoryPart.selector, "impact OS"
            )
        );
        verifier.requestMergedStatus("mandatedisrael", "impact OS", 42);

        vm.expectRevert(GitHubPullRequestVerifier.InvalidPullRequestNumber.selector);
        verifier.requestMergedStatus("mandatedisrael", "impactOS", 0);
    }

    function testRejectsRequestWhenContractCannotFundIt() public {
        GitHubPullRequestVerifier emptyVerifier =
            new GitHubPullRequestVerifier(ISomniaAgents(address(agents)), address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                GitHubPullRequestVerifier.InsufficientContractBalance.selector, 0.12 ether, 0
            )
        );
        emptyVerifier.requestMergedStatus("mandatedisrael", "impactOS", 42);
    }
}
