// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { GrantState, MilestoneInput, MilestoneView } from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowEvidenceTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    bytes32 private constant MANIFEST_HASH = keccak256("manifest");

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.warp(1_750_000_000);
    }

    function testGranteeSubmitsEvidenceForFundedMilestone() public {
        uint256 grantId = _createAndFundGrant();

        vm.warp(block.timestamp + 1 days);
        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, MANIFEST_HASH, "ipfs://manifest");

        MilestoneView memory milestone = escrow.getMilestone(grantId, 1);
        assertEq(milestone.pullRequestNumber, 42);
        assertEq(milestone.evidenceManifestHash, MANIFEST_HASH);
        assertEq(milestone.evidenceURI, "ipfs://manifest");
        assertEq(milestone.submittedAt, 1_750_000_000 + 1 days);
    }

    function testRejectsEvidenceForUnfundedGrant() public {
        uint256 grantId = _createGrant();

        vm.prank(GRANTEE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, grantId, GrantState.Created
            )
        );
        escrow.submitEvidence(grantId, 1, 42, MANIFEST_HASH, "ipfs://manifest");
    }

    function testRejectsEvidenceFromNonGrantee() public {
        uint256 grantId = _createAndFundGrant();

        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyGrantee.selector, FUNDER));
        escrow.submitEvidence(grantId, 1, 42, MANIFEST_HASH, "ipfs://manifest");
    }

    function testRejectsEvidenceAfterSubmissionDeadline() public {
        uint256 grantId = _createAndFundGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).submissionDeadline;
        vm.warp(uint256(deadline) + 1);

        vm.prank(GRANTEE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.SubmissionDeadlinePassed.selector, grantId, 1, deadline
            )
        );
        escrow.submitEvidence(grantId, 1, 42, MANIFEST_HASH, "ipfs://manifest");
    }

    function testRejectsMalformedEvidence() public {
        uint256 grantId = _createAndFundGrant();

        vm.startPrank(GRANTEE);
        vm.expectRevert(ImpactEscrow.InvalidPullRequestNumber.selector);
        escrow.submitEvidence(grantId, 1, 0, MANIFEST_HASH, "ipfs://manifest");

        vm.expectRevert(ImpactEscrow.InvalidEvidenceManifest.selector);
        escrow.submitEvidence(grantId, 1, 42, bytes32(0), "ipfs://manifest");

        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidURI.selector, 1, ""));
        escrow.submitEvidence(grantId, 1, 42, MANIFEST_HASH, "");
        vm.stopPrank();
    }

    function _createAndFundGrant() private returns (uint256 grantId) {
        grantId = _createGrant();
        uint256 amount = escrow.getGrant(grantId).totalPrincipal;
        usdc.mint(FUNDER, amount);

        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), amount);
        escrow.fundGrant(grantId);
        vm.stopPrank();
    }

    function _createGrant() private returns (uint256) {
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
        return escrow.createGrant(GRANTEE, inputs);
    }
}
