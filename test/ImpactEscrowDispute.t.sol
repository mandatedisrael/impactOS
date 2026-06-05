// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import {
    MilestoneInput,
    MilestoneState,
    VerificationVerdict
} from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowDisputeTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant ADAPTER = address(0xADA7);
    address private constant ATTACKER = address(0xBAD);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
        vm.warp(1_750_000_000);
    }

    function testFunderChallengesDuringWindowWithExactBond() public {
        uint256 grantId = _proposedGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).challengeDeadline;
        vm.warp(deadline);
        _fundAndApproveBond();

        vm.prank(FUNDER);
        escrow.challengeMilestone(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Disputed));
        assertEq(escrow.totalDisputeBonds(), 25e6);
        assertEq(usdc.balanceOf(address(escrow)), 1_025e6);
    }

    function testRejectsLateChallengeAndMissingBondAllowance() public {
        uint256 lateGrantId = _proposedGrant();
        uint64 deadline = escrow.getMilestone(lateGrantId, 1).challengeDeadline;
        vm.warp(uint256(deadline) + 1);

        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.ChallengePeriodElapsed.selector, lateGrantId, 1, deadline
            )
        );
        escrow.challengeMilestone(lateGrantId, 1);

        uint256 noAllowanceGrantId = _proposedGrant();
        usdc.mint(FUNDER, 25e6);
        vm.prank(FUNDER);
        vm.expectRevert();
        escrow.challengeMilestone(noAllowanceGrantId, 1);

        assertEq(
            uint256(escrow.getMilestone(noAllowanceGrantId, 1).state),
            uint256(MilestoneState.ProposedApproval)
        );
        assertEq(escrow.totalDisputeBonds(), 0);
    }

    function testResolverApprovalAwardsBondAndPrincipalToGrantee() public {
        uint256 grantId = _disputedGrant();

        vm.prank(RESOLVER);
        escrow.resolveDispute(grantId, 1, true);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Claimable));
        assertEq(escrow.totalDisputeBonds(), 0);
        assertEq(escrow.claimablePrincipal(GRANTEE), 25e6);

        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);
        assertEq(escrow.claimablePrincipal(GRANTEE), 1_025e6);

        vm.prank(GRANTEE);
        escrow.withdrawPrincipal(GRANTEE);
        assertEq(usdc.balanceOf(GRANTEE), 1_025e6);
    }

    function testResolverRejectionReturnsBondAndPrincipalToFunder() public {
        uint256 grantId = _disputedGrant();

        vm.prank(RESOLVER);
        escrow.resolveDispute(grantId, 1, false);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Refundable));
        assertEq(escrow.claimablePrincipal(FUNDER), 25e6);

        vm.prank(FUNDER);
        escrow.refundMilestone(grantId, 1);
        assertEq(escrow.claimablePrincipal(FUNDER), 1_025e6);

        vm.prank(FUNDER);
        escrow.withdrawPrincipal(FUNDER);
        assertEq(usdc.balanceOf(FUNDER), 1_025e6);
    }

    function testOnlyResolverMayResolveAndDisputeCannotResolveTwice() public {
        uint256 grantId = _disputedGrant();

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyResolver.selector, ATTACKER));
        escrow.resolveDispute(grantId, 1, true);

        vm.prank(RESOLVER);
        escrow.resolveDispute(grantId, 1, true);

        vm.prank(RESOLVER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidMilestoneState.selector, grantId, 1, MilestoneState.Claimable
            )
        );
        escrow.resolveDispute(grantId, 1, false);
    }

    function testResolverHandlesManualReviewWithoutMovingFunds() public {
        uint256 approvedGrantId = _manualReviewGrant();
        vm.prank(RESOLVER);
        escrow.resolveManualReview(approvedGrantId, 1, true);
        assertEq(
            uint256(escrow.getMilestone(approvedGrantId, 1).state),
            uint256(MilestoneState.Claimable)
        );

        uint256 rejectedGrantId = _manualReviewGrant();
        vm.prank(RESOLVER);
        escrow.resolveManualReview(rejectedGrantId, 1, false);
        assertEq(
            uint256(escrow.getMilestone(rejectedGrantId, 1).state),
            uint256(MilestoneState.Refundable)
        );

        assertEq(escrow.totalClaimablePrincipal(), 0);
        assertEq(escrow.totalDisputeBonds(), 0);
    }

    function _disputedGrant() private returns (uint256 grantId) {
        grantId = _proposedGrant();
        _fundAndApproveBond();
        vm.prank(FUNDER);
        escrow.challengeMilestone(grantId, 1);
    }

    function _fundAndApproveBond() private {
        usdc.mint(FUNDER, 25e6);
        vm.prank(FUNDER);
        usdc.approve(address(escrow), 25e6);
    }

    function _manualReviewGrant() private returns (uint256 grantId) {
        grantId = _readyGrant();
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Failed);
    }

    function _proposedGrant() private returns (uint256 grantId) {
        grantId = _readyGrant();
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);
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
}
