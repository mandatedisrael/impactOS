// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import {
    MilestoneInput,
    MilestoneState,
    MilestoneView,
    VerificationVerdict
} from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowVerificationBoundaryTest is Test {
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
        vm.warp(1_750_000_000);

        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
    }

    function testGuardianConfiguresAdapterOnlyOnce() public {
        ImpactEscrow freshEscrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyGuardian.selector, ATTACKER));
        freshEscrow.configureVerifierAdapter(ADAPTER);

        vm.prank(GUARDIAN);
        freshEscrow.configureVerifierAdapter(ADAPTER);
        assertEq(freshEscrow.verifierAdapter(), ADAPTER);

        vm.prank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.VerifierAdapterAlreadyConfigured.selector, ADAPTER)
        );
        freshEscrow.configureVerifierAdapter(address(0xB0B));
    }

    function testAdapterStartsVerificationAfterEvidenceSubmission() public {
        uint256 grantId = _readyGrant();

        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);

        MilestoneView memory milestone = escrow.getMilestone(grantId, 1);
        assertEq(attempt, 1);
        assertEq(milestone.verificationAttempt, 1);
        assertEq(uint256(milestone.state), uint256(MilestoneState.Verifying));
        assertEq(uint256(milestone.verificationVerdict), uint256(VerificationVerdict.None));
    }

    function testRejectsVerificationStartWithoutEvidence() public {
        uint256 grantId = _fundedGrant();

        vm.prank(ADAPTER);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.EvidenceNotSubmitted.selector, grantId, 1)
        );
        escrow.startVerification(grantId, 1);
    }

    function testRejectsVerificationActionsFromUnauthorizedCaller() public {
        uint256 grantId = _readyGrant();

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyVerifierAdapter.selector, ATTACKER));
        escrow.startVerification(grantId, 1);

        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyVerifierAdapter.selector, ATTACKER));
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);
    }

    function testApprovedVerdictOpensChallengePeriod() public {
        uint256 grantId = _readyGrant();
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);

        MilestoneView memory milestone = escrow.getMilestone(grantId, 1);
        assertEq(uint256(milestone.state), uint256(MilestoneState.ProposedApproval));
        assertEq(uint256(milestone.verificationVerdict), uint256(VerificationVerdict.Approved));
        assertEq(milestone.challengeDeadline, block.timestamp + 2 days);
    }

    function testNonApprovalVerdictsRequireManualReview() public {
        VerificationVerdict[3] memory verdicts = [
            VerificationVerdict.ManualReview,
            VerificationVerdict.Failed,
            VerificationVerdict.TimedOut
        ];

        for (uint256 i; i < verdicts.length; ++i) {
            uint256 grantId = _readyGrant();
            vm.prank(ADAPTER);
            uint32 attempt = escrow.startVerification(grantId, 1);

            vm.prank(ADAPTER);
            escrow.recordVerificationVerdict(grantId, 1, attempt, verdicts[i]);

            MilestoneView memory milestone = escrow.getMilestone(grantId, 1);
            assertEq(uint256(milestone.state), uint256(MilestoneState.ManualReview));
            assertEq(uint256(milestone.verificationVerdict), uint256(verdicts[i]));
            assertEq(milestone.challengeDeadline, 0);
        }
    }

    function testRejectsStaleInvalidAndDuplicateVerdicts() public {
        uint256 grantId = _readyGrant();
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);

        vm.prank(ADAPTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.StaleVerificationAttempt.selector, attempt, attempt + 1
            )
        );
        escrow.recordVerificationVerdict(grantId, 1, attempt + 1, VerificationVerdict.Approved);

        vm.prank(ADAPTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidVerificationVerdict.selector, VerificationVerdict.None
            )
        );
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.None);

        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);

        vm.prank(ADAPTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidMilestoneState.selector,
                grantId,
                1,
                MilestoneState.ProposedApproval
            )
        );
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);
    }

    function _readyGrant() private returns (uint256 grantId) {
        grantId = _fundedGrant();
        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");
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
