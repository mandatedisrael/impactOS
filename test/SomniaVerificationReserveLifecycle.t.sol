// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { SomniaVerificationAdapter } from "../src/SomniaVerificationAdapter.sol";
import { MilestoneInput } from "../src/interfaces/IImpactEscrow.sol";
import { AgentResponse, ResponseStatus } from "../src/interfaces/ISomniaAgents.sol";
import { MockSomniaAgents } from "./mocks/MockSomniaAgents.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract SomniaVerificationReserveLifecycleTest is Test {
    MockUSDC private usdc;
    MockSomniaAgents private agents;
    ImpactEscrow private escrow;
    SomniaVerificationAdapter private adapter;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address payable private constant RECIPIENT = payable(address(0xCA11));
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

    function testFunderWithdrawsUnusedReserveAfterMilestoneSettlement() public {
        (uint256 grantId, uint256 requestId) = _requestWithReserve(0.2 ether);
        AgentResponse[] memory responses = new AgentResponse[](2);
        responses[0] = _response(true);
        responses[1] = _response(true);
        agents.deliverResponse(requestId, responses, ResponseStatus.Success, 2);

        uint64 challengeDeadline = escrow.getMilestone(grantId, 1).challengeDeadline;
        vm.warp(uint256(challengeDeadline) + 1);
        escrow.finalizeApproval(grantId, 1);
        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);

        vm.prank(FUNDER);
        adapter.withdrawVerificationReserve(grantId, 1, RECIPIENT);

        assertEq(RECIPIENT.balance, 0.08 ether);
        assertEq(adapter.verificationReserve(grantId, 1), 0);
    }

    function testReserveRemainsLockedUntilMilestoneIsPaidOrRefunded() public {
        uint256 grantId = _readyGrant();
        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.2 ether }(grantId, 1);

        vm.prank(FUNDER);
        vm.expectRevert();
        adapter.withdrawVerificationReserve(grantId, 1, RECIPIENT);

        assertEq(adapter.verificationReserve(grantId, 1), 0.2 ether);
    }

    function testGuardianAssignsTrackedRebateToMilestoneReserve() public {
        uint256 grantId = _readyGrant();
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(adapter)).call{ value: 0.03 ether }("");
        assertTrue(success);

        vm.prank(GUARDIAN);
        adapter.assignUnallocatedRebate(grantId, 1, 0.02 ether);

        assertEq(adapter.unallocatedRebates(), 0.01 ether);
        assertEq(adapter.verificationReserve(grantId, 1), 0.02 ether);
    }

    function testRejectsUnauthorizedRebateAssignmentAndReserveWithdrawal() public {
        uint256 grantId = _readyGrant();
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(adapter)).call{ value: 0.03 ether }("");
        assertTrue(success);

        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(SomniaVerificationAdapter.OnlyRebateAllocator.selector, ATTACKER)
        );
        adapter.assignUnallocatedRebate(grantId, 1, 0.01 ether);

        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.12 ether }(grantId, 1);
        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(SomniaVerificationAdapter.OnlyFunder.selector, ATTACKER)
        );
        adapter.withdrawVerificationReserve(grantId, 1, RECIPIENT);
    }

    function _requestWithReserve(uint256 reserve)
        private
        returns (uint256 grantId, uint256 requestId)
    {
        grantId = _readyGrant();
        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: reserve }(grantId, 1);
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

    function _response(bool merged) private pure returns (AgentResponse memory) {
        return AgentResponse({
            validator: address(0xCAFE),
            result: abi.encode(merged),
            status: ResponseStatus.Success,
            receipt: 0,
            timestamp: 0,
            executionCost: 0
        });
    }
}
