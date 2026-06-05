// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { SomniaVerificationAdapter } from "../src/SomniaVerificationAdapter.sol";
import {
    MilestoneInput,
    MilestoneState,
    VerificationVerdict
} from "../src/interfaces/IImpactEscrow.sol";
import { AgentRequest, AgentResponse, ResponseStatus } from "../src/interfaces/ISomniaAgents.sol";
import { MockSomniaAgents } from "./mocks/MockSomniaAgents.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract SomniaVerificationAdapterCallbackTest is Test {
    MockUSDC private usdc;
    MockSomniaAgents private agents;
    ImpactEscrow private escrow;
    SomniaVerificationAdapter private adapter;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant ATTACKER = address(0xBAD);

    function setUp() public {
        usdc = new MockUSDC();
        agents = new MockSomniaAgents();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        adapter = new SomniaVerificationAdapter(escrow, agents, GUARDIAN);

        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(address(adapter));
        vm.warp(1_750_000_000);
        vm.deal(FUNDER, 10 ether);
    }

    function testMergedConsensusProposesMilestoneApproval() public {
        (uint256 grantId, uint256 requestId) = _request();
        AgentResponse[] memory responses = new AgentResponse[](3);
        responses[0] = _response(ResponseStatus.Success, abi.encode(true));
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));
        responses[2] = _response(ResponseStatus.Success, abi.encode(false));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        assertEq(
            uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.ProposedApproval)
        );
        assertEq(
            uint256(escrow.getMilestone(grantId, 1).verificationVerdict),
            uint256(VerificationVerdict.Approved)
        );
        (,,, bool consumed) = adapter.requests(requestId);
        assertTrue(consumed);
    }

    function testNotMergedConsensusRequiresManualReview() public {
        (uint256 grantId, uint256 requestId) = _request();
        AgentResponse[] memory responses = new AgentResponse[](3);
        responses[0] = _response(ResponseStatus.Success, abi.encode(false));
        responses[1] = _response(ResponseStatus.Success, abi.encode(false));
        responses[2] = _response(ResponseStatus.Success, abi.encode(true));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        assertEq(
            uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.ManualReview)
        );
        assertEq(
            uint256(escrow.getMilestone(grantId, 1).verificationVerdict),
            uint256(VerificationVerdict.Failed)
        );
    }

    function testMalformedResponseCannotApproveMilestone() public {
        (uint256 grantId, uint256 requestId) = _request();
        AgentResponse[] memory responses = new AgentResponse[](2);
        responses[0] = _response(ResponseStatus.Success, hex"02");
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        assertEq(
            uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.ManualReview)
        );
        assertEq(
            uint256(escrow.getMilestone(grantId, 1).verificationVerdict),
            uint256(VerificationVerdict.Failed)
        );
    }

    function testPlatformFailureAndTimeoutRequireManualReview() public {
        AgentResponse[] memory noResponses = new AgentResponse[](0);

        (uint256 failedGrantId, uint256 failedRequestId) = _request();
        agents.deliverResponse(failedRequestId, noResponses, ResponseStatus.Failed, 2);
        assertEq(
            uint256(escrow.getMilestone(failedGrantId, 1).verificationVerdict),
            uint256(VerificationVerdict.Failed)
        );

        (uint256 timedOutGrantId, uint256 timedOutRequestId) = _request();
        agents.deliverResponse(timedOutRequestId, noResponses, ResponseStatus.TimedOut, 2);
        assertEq(
            uint256(escrow.getMilestone(timedOutGrantId, 1).verificationVerdict),
            uint256(VerificationVerdict.TimedOut)
        );
    }

    function testRejectsSpoofedCallback() public {
        (, uint256 requestId) = _request();
        AgentResponse[] memory noResponses = new AgentResponse[](0);
        AgentRequest memory details = agents.getRequest(requestId);

        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(SomniaVerificationAdapter.OnlyPlatform.selector, ATTACKER)
        );
        adapter.handleResponse(requestId, noResponses, ResponseStatus.Success, details);
    }

    function testRejectsMismatchedCallbackDetails() public {
        (, uint256 requestId) = _request();
        AgentResponse[] memory noResponses = new AgentResponse[](0);
        AgentRequest memory details = agents.getRequest(requestId);
        details.callbackAddress = ATTACKER;

        vm.expectRevert(
            abi.encodeWithSelector(
                SomniaVerificationAdapter.InvalidCallbackDetails.selector, requestId
            )
        );
        agents.deliverCustomResponse(
            address(adapter), requestId, noResponses, ResponseStatus.Success, details
        );
    }

    function testRejectsDuplicateCallback() public {
        (, uint256 requestId) = _request();
        AgentResponse[] memory responses = new AgentResponse[](2);
        responses[0] = _response(ResponseStatus.Success, abi.encode(true));
        responses[1] = _response(ResponseStatus.Success, abi.encode(true));

        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                SomniaVerificationAdapter.RequestAlreadyConsumed.selector, requestId
            )
        );
        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);
    }

    function _request() private returns (uint256 grantId, uint256 requestId) {
        grantId = _readyGrant();

        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.12 ether }(grantId, 1);
        requestId = adapter.requestObjectiveVerification(grantId, 1);
    }

    function _readyGrant() private returns (uint256 grantId) {
        MilestoneInput[] memory inputs = new MilestoneInput[](1);
        inputs[0] = MilestoneInput({
            amount: 1_000e6,
            repositoryOwner: "mandatedisrael",
            repositoryName: "impactOS",
            expectedBaseBranch: "main",
            acceptanceCriteriaHash: keccak256("criteria"),
            acceptanceCriteriaURI: "ipfs://criteria",
            submissionDeadline: uint64(block.timestamp + 30 days),
            challengePeriod: 2 days
        });

        vm.prank(FUNDER);
        grantId = escrow.createGrant(GRANTEE, inputs);
        usdc.mint(FUNDER, 1_000e6);

        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");
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
