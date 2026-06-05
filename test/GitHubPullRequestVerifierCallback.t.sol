// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { GitHubPullRequestVerifier } from "../src/GitHubPullRequestVerifier.sol";
import {
    AgentRequest,
    AgentResponse,
    ISomniaAgents,
    ResponseStatus
} from "../src/interfaces/ISomniaAgents.sol";
import { MockSomniaAgents } from "./mocks/MockSomniaAgents.sol";

contract GitHubPullRequestVerifierCallbackTest is Test {
    MockSomniaAgents private agents;
    GitHubPullRequestVerifier private verifier;

    address private constant ATTACKER = address(0xBEEF);

    function setUp() public {
        agents = new MockSomniaAgents();
        verifier = new GitHubPullRequestVerifier(ISomniaAgents(address(agents)), address(this));
        vm.deal(address(verifier), 1 ether);
    }

    function testResolvesMergedWhenThresholdAgrees() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](3);
        responses[0] = _response(ResponseStatus.Success, abi.encode(true));
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));
        responses[2] = _response(ResponseStatus.Success, abi.encode(false));

        vm.warp(1_750_000_100);
        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        GitHubPullRequestVerifier.Verification memory verification =
            verifier.getVerification(requestId);
        assertEq(
            uint256(verification.status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.Merged)
        );
        assertEq(verification.resolvedAt, 1_750_000_100);
    }

    function testResolvesNotMergedWhenThresholdAgrees() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](3);
        responses[0] = _response(ResponseStatus.Success, abi.encode(false));
        responses[1] = _response(ResponseStatus.Success, abi.encode(false));
        responses[2] = _response(ResponseStatus.Failed, "");

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        assertEq(
            uint256(verifier.getVerification(requestId).status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.NotMerged)
        );
    }

    function testMalformedAgentResultFailsWithoutRevertingCallback() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](2);
        responses[0] = _response(ResponseStatus.Success, hex"02");
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        assertEq(
            uint256(verifier.getVerification(requestId).status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.Failed)
        );
    }

    function testMapsPlatformTimeoutAndFailureStatuses() public {
        AgentResponse[] memory noResponses = new AgentResponse[](0);

        uint256 timedOutRequestId = _request();
        agents.deliverResponse(timedOutRequestId, noResponses, ResponseStatus.TimedOut, 2);
        assertEq(
            uint256(verifier.getVerification(timedOutRequestId).status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.TimedOut)
        );

        uint256 failedRequestId = _request();
        agents.deliverResponse(failedRequestId, noResponses, ResponseStatus.Failed, 2);
        assertEq(
            uint256(verifier.getVerification(failedRequestId).status),
            uint256(GitHubPullRequestVerifier.VerificationStatus.Failed)
        );
    }

    function testRejectsCallbackFromAnyAddressExceptPlatform() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](0);
        AgentRequest memory details = agents.getRequest(requestId);

        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(GitHubPullRequestVerifier.OnlyPlatform.selector, ATTACKER)
        );
        verifier.handleResponse(requestId, responses, ResponseStatus.Success, details);
    }

    function testRejectsMismatchedCallbackDetails() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](0);
        AgentRequest memory details = agents.getRequest(requestId);
        details.callbackSelector = bytes4(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                GitHubPullRequestVerifier.InvalidCallbackDetails.selector, requestId
            )
        );
        agents.deliverCustomResponse(
            address(verifier), requestId, responses, ResponseStatus.Success, details
        );
    }

    function testRejectsSecondResolutionAttempt() public {
        uint256 requestId = _request();
        AgentResponse[] memory responses = new AgentResponse[](2);
        responses[0] = _response(ResponseStatus.Success, abi.encode(true));
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                GitHubPullRequestVerifier.RequestAlreadyResolved.selector, requestId
            )
        );
        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);
    }

    function _request() private returns (uint256) {
        return verifier.requestMergedStatus("mandatedisrael", "impactOS", 42);
    }

    function _response(ResponseStatus status, bytes memory result)
        private
        pure
        returns (AgentResponse memory)
    {
        return AgentResponse({
            validator: address(0xCAFE),
            result: result,
            status: status,
            receipt: 0,
            timestamp: 0,
            executionCost: 0
        });
    }
}
