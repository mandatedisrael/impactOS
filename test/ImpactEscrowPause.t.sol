// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { MilestoneInput, VerificationVerdict } from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowPauseTest is Test {
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
        escrow = new ImpactEscrow(IERC20(address(usdc)), GUARDIAN, RESOLVER);
        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
        vm.warp(1_750_000_000);
    }

    function testOnlyGuardianMayPauseAndUnpause() public {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyGuardian.selector, ATTACKER));
        escrow.pause();

        vm.prank(GUARDIAN);
        escrow.pause();
        assertTrue(escrow.paused());

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyGuardian.selector, ATTACKER));
        escrow.unpause();

        vm.prank(GUARDIAN);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    function testPauseBlocksNewGrantFundingEvidenceAndVerification() public {
        uint256 createdGrantId = _createGrant();
        uint256 fundedGrantId = _fundedGrant();
        uint256 readyGrantId = _fundedGrant();
        vm.prank(GRANTEE);
        escrow.submitEvidence(readyGrantId, 1, 42, keccak256("manifest"), "ipfs://manifest");

        vm.prank(GUARDIAN);
        escrow.pause();

        vm.prank(FUNDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.createGrant(GRANTEE, _inputs());

        usdc.mint(FUNDER, 1_000e6);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.fundGrant(createdGrantId);
        vm.stopPrank();

        vm.prank(GRANTEE);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.submitEvidence(fundedGrantId, 1, 42, keccak256("manifest"), "ipfs://manifest");

        vm.prank(ADAPTER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.startVerification(readyGrantId, 1);
    }

    function testPauseDoesNotTrapApprovedPrincipal() public {
        uint256 grantId = _approvedGrant();
        uint64 deadline = escrow.getMilestone(grantId, 1).challengeDeadline;
        vm.warp(uint256(deadline) + 1);

        vm.prank(GUARDIAN);
        escrow.pause();

        escrow.finalizeApproval(grantId, 1);
        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);
        vm.prank(GRANTEE);
        escrow.withdrawPrincipal(GRANTEE);

        assertEq(usdc.balanceOf(GRANTEE), 1_000e6);
    }

    function testUnpauseRestoresRiskEntryPoints() public {
        vm.prank(GUARDIAN);
        escrow.pause();
        vm.prank(GUARDIAN);
        escrow.unpause();

        vm.prank(FUNDER);
        uint256 grantId = escrow.createGrant(GRANTEE, _inputs());
        assertEq(grantId, 1);
    }

    function _approvedGrant() private returns (uint256 grantId) {
        grantId = _fundedGrant();
        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);
    }

    function _fundedGrant() private returns (uint256 grantId) {
        grantId = _createGrant();
        usdc.mint(FUNDER, 1_000e6);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        escrow.fundGrant(grantId);
        vm.stopPrank();
    }

    function _createGrant() private returns (uint256) {
        vm.prank(FUNDER);
        return escrow.createGrant(GRANTEE, _inputs());
    }

    function _inputs() private view returns (MilestoneInput[] memory inputs) {
        inputs = new MilestoneInput[](1);
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
    }
}
