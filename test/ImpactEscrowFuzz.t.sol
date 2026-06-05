// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import {
    GrantState, MilestoneInput, VerificationVerdict
} from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowFuzzTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant RECIPIENT = address(0xCA11);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant ADAPTER = address(0xADA7);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
        vm.warp(1_750_000_000);
    }

    function testFuzz_FundingPreservesExactPrincipal(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000_000e6);
        uint256 grantId = _createGrant(amount);

        usdc.mint(FUNDER, amount);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), amount);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        assertEq(escrow.getGrant(grantId).remainingPrincipal, amount);
        assertEq(escrow.totalEscrowedPrincipal(), amount);
        assertEq(usdc.balanceOf(address(escrow)), amount);
    }

    function testFuzz_ResolvedMilestoneConservesPrincipal(uint96 rawAmount, bool approve) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000_000e6);
        uint256 grantId = _manualReviewGrant(amount);

        vm.prank(RESOLVER);
        escrow.resolveManualReview(grantId, 1, approve);

        address beneficiary;
        if (approve) {
            beneficiary = GRANTEE;
            vm.prank(GRANTEE);
            escrow.claimMilestone(grantId, 1);
        } else {
            beneficiary = FUNDER;
            vm.prank(FUNDER);
            escrow.refundMilestone(grantId, 1);
        }

        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Completed));
        assertEq(escrow.totalEscrowedPrincipal(), 0);
        assertEq(escrow.totalSettledPrincipal(), amount);
        assertEq(escrow.totalClaimableUSDC(), amount);
        assertEq(escrow.claimableUSDC(beneficiary), amount);
        assertEq(usdc.balanceOf(address(escrow)), amount);

        vm.prank(beneficiary);
        escrow.withdrawPrincipal(RECIPIENT);

        assertEq(usdc.balanceOf(RECIPIENT), amount);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalClaimableUSDC(), 0);
        assertEq(escrow.totalWithdrawnUSDC(), amount);
    }

    function testFuzz_MultipleMilestonesSumWithoutAccountingDrift(
        uint64 firstRaw,
        uint64 secondRaw,
        uint64 thirdRaw
    ) public {
        uint256 first = bound(uint256(firstRaw), 1, 1_000_000e6);
        uint256 second = bound(uint256(secondRaw), 1, 1_000_000e6);
        uint256 third = bound(uint256(thirdRaw), 1, 1_000_000e6);
        uint256 total = first + second + third;

        MilestoneInput[] memory inputs = new MilestoneInput[](3);
        inputs[0] = _input(first);
        inputs[1] = _input(second);
        inputs[2] = _input(third);

        vm.prank(FUNDER);
        uint256 grantId = escrow.createGrant(GRANTEE, inputs);
        assertEq(escrow.getGrant(grantId).totalPrincipal, total);

        usdc.mint(FUNDER, total);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), total);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        assertEq(escrow.getGrant(grantId).remainingPrincipal, total);
        assertEq(escrow.totalEscrowedPrincipal(), total);
        assertEq(usdc.balanceOf(address(escrow)), total);
    }

    function _manualReviewGrant(uint256 amount) private returns (uint256 grantId) {
        grantId = _createGrant(amount);
        usdc.mint(FUNDER, amount);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), amount);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        vm.prank(GRANTEE);
        escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Failed);
    }

    function _createGrant(uint256 amount) private returns (uint256) {
        MilestoneInput[] memory inputs = new MilestoneInput[](1);
        inputs[0] = _input(amount);
        vm.prank(FUNDER);
        return escrow.createGrant(GRANTEE, inputs);
    }

    function _input(uint256 amount) private view returns (MilestoneInput memory) {
        return MilestoneInput({
            amount: amount,
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
