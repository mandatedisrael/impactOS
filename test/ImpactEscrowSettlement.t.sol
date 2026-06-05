// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import {
    GrantState,
    MilestoneInput,
    MilestoneState,
    VerificationVerdict
} from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowSettlementTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant RECIPIENT = address(0xCA11);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant ADAPTER = address(0xADA7);
    address private constant KEEPER = address(0xC0DE);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
        vm.warp(1_750_000_000);
    }

    function testUnchallengedApprovalBecomesClaimableAfterDeadline() public {
        uint256 grantId = _approvedGrant();
        uint64 challengeDeadline = escrow.getMilestone(grantId, 1).challengeDeadline;

        vm.warp(challengeDeadline);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.ChallengePeriodActive.selector, grantId, 1, challengeDeadline
            )
        );
        escrow.finalizeApproval(grantId, 1);

        vm.warp(uint256(challengeDeadline) + 1);
        vm.prank(KEEPER);
        escrow.finalizeApproval(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Claimable));
        assertEq(escrow.totalEscrowedPrincipal(), 1_000e6);
        assertEq(escrow.totalClaimableUSDC(), 0);
    }

    function testGranteeClaimsThenWithdrawsPrincipal() public {
        uint256 grantId = _claimableGrant();

        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Paid));
        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Completed));
        assertEq(escrow.getGrant(grantId).remainingPrincipal, 0);
        assertEq(escrow.totalEscrowedPrincipal(), 0);
        assertEq(escrow.claimableUSDC(GRANTEE), 1_000e6);
        assertEq(escrow.totalClaimableUSDC(), 1_000e6);
        assertEq(usdc.balanceOf(address(escrow)), 1_000e6);

        vm.prank(GRANTEE);
        escrow.withdrawPrincipal(RECIPIENT);

        assertEq(usdc.balanceOf(RECIPIENT), 1_000e6);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(escrow.claimableUSDC(GRANTEE), 0);
        assertEq(escrow.totalClaimableUSDC(), 0);
        assertEq(escrow.totalWithdrawnUSDC(), 1_000e6);
    }

    function testRejectsClaimByNonGranteeAndDuplicateClaim() public {
        uint256 grantId = _claimableGrant();

        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyGrantee.selector, FUNDER));
        escrow.claimMilestone(grantId, 1);

        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);

        vm.prank(GRANTEE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, grantId, GrantState.Completed
            )
        );
        escrow.claimMilestone(grantId, 1);
    }

    function testRejectsEmptyAndZeroRecipientWithdrawals() public {
        vm.prank(GRANTEE);
        vm.expectRevert(ImpactEscrow.InvalidRecipient.selector);
        escrow.withdrawPrincipal(address(0));

        vm.prank(GRANTEE);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.NothingToWithdraw.selector, GRANTEE));
        escrow.withdrawPrincipal(RECIPIENT);
    }

    function _claimableGrant() private returns (uint256 grantId) {
        grantId = _approvedGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).challengeDeadline;
        vm.warp(uint256(deadline) + 1);
        escrow.finalizeApproval(grantId, 1);
    }

    function _approvedGrant() private returns (uint256 grantId) {
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
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);
    }
}
