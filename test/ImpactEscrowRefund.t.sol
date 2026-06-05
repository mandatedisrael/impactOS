// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { GrantState, MilestoneInput, MilestoneState } from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowRefundTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant RECIPIENT = address(0xCA11);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant KEEPER = address(0xC0DE);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.warp(1_750_000_000);
    }

    function testExpiredUnsubmittedMilestoneBecomesRefundable() public {
        uint256 grantId = _fundedGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).submissionDeadline;

        vm.warp(deadline);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.SubmissionDeadlineActive.selector, grantId, 1, deadline
            )
        );
        escrow.markExpiredMilestoneRefundable(grantId, 1);

        vm.warp(uint256(deadline) + 1);
        vm.prank(KEEPER);
        escrow.markExpiredMilestoneRefundable(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Refundable));
    }

    function testSubmittedEvidencePreventsExpiryRefund() public {
        uint256 grantId = _fundedGrant();
        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");

        vm.warp(uint256(escrow.getMilestone(grantId, 1).submissionDeadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.SubmittedMilestoneCannotExpire.selector, grantId, 1)
        );
        escrow.markExpiredMilestoneRefundable(grantId, 1);
    }

    function testFunderRefundsAndWithdrawsExpiredPrincipal() public {
        uint256 grantId = _refundableGrant();

        vm.prank(FUNDER);
        escrow.refundMilestone(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Refunded));
        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Completed));
        assertEq(escrow.totalEscrowedPrincipal(), 0);
        assertEq(escrow.claimablePrincipal(FUNDER), 1_000e6);
        assertEq(escrow.totalClaimablePrincipal(), 1_000e6);

        vm.prank(FUNDER);
        escrow.withdrawPrincipal(RECIPIENT);
        assertEq(usdc.balanceOf(RECIPIENT), 1_000e6);
        assertEq(escrow.totalWithdrawnPrincipal(), 1_000e6);
    }

    function testRejectsRefundByNonFunderAndDuplicateRefund() public {
        uint256 grantId = _refundableGrant();

        vm.prank(GRANTEE);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyFunder.selector, GRANTEE));
        escrow.refundMilestone(grantId, 1);

        vm.prank(FUNDER);
        escrow.refundMilestone(grantId, 1);

        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, grantId, GrantState.Completed
            )
        );
        escrow.refundMilestone(grantId, 1);
    }

    function _refundableGrant() private returns (uint256 grantId) {
        grantId = _fundedGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).submissionDeadline;
        vm.warp(uint256(deadline) + 1);
        escrow.markExpiredMilestoneRefundable(grantId, 1);
    }

    function _fundedGrant() private returns (uint256 grantId) {
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
    }
}
