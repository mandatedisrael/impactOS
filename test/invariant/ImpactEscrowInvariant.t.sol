// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../../src/ImpactEscrow.sol";
import {
    GrantState,
    MilestoneInput,
    MilestoneState,
    VerificationVerdict
} from "../../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "../mocks/MockUSDC.sol";

contract ImpactEscrowHandler is Test {
    MockUSDC public immutable usdc;
    ImpactEscrow public immutable escrow;

    address public constant FUNDER = address(0xF00D);
    address public constant GRANTEE = address(0xBEEF);
    address public constant GUARDIAN = address(0xA11CE);
    address public constant RESOLVER = address(0xCAFE);
    address public constant ADAPTER = address(0xADA7);

    uint256[] private _grantIds;

    constructor(MockUSDC usdc_, ImpactEscrow escrow_) {
        usdc = usdc_;
        escrow = escrow_;
    }

    function createAndFund(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e6);
        MilestoneInput[] memory inputs = new MilestoneInput[](1);
        inputs[0] = _input(amount);

        vm.prank(FUNDER);
        uint256 grantId = escrow.createGrant(GRANTEE, inputs);
        usdc.mint(FUNDER, amount);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), amount);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        _grantIds.push(grantId);
    }

    function approveAndSettle(uint256 seed) external {
        uint256 grantId = _pendingGrant(seed);
        if (grantId == 0) return;

        _submitEvidence(grantId);
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);

        vm.warp(uint256(escrow.getMilestone(grantId, 1).challengeDeadline) + 1);
        escrow.finalizeApproval(grantId, 1);
        vm.prank(GRANTEE);
        escrow.claimMilestone(grantId, 1);
    }

    function manualReviewAndSettle(uint256 seed, bool approve) external {
        uint256 grantId = _pendingGrant(seed);
        if (grantId == 0) return;

        _submitEvidence(grantId);
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Failed);
        vm.prank(RESOLVER);
        escrow.resolveManualReview(grantId, 1, approve);

        if (approve) {
            vm.prank(GRANTEE);
            escrow.claimMilestone(grantId, 1);
        } else {
            vm.prank(FUNDER);
            escrow.refundMilestone(grantId, 1);
        }
    }

    function challengeAndSettle(uint256 seed, bool approve) external {
        uint256 grantId = _pendingGrant(seed);
        if (grantId == 0) return;

        _submitEvidence(grantId);
        vm.prank(ADAPTER);
        uint32 attempt = escrow.startVerification(grantId, 1);
        vm.prank(ADAPTER);
        escrow.recordVerificationVerdict(grantId, 1, attempt, VerificationVerdict.Approved);

        usdc.mint(FUNDER, escrow.DISPUTE_BOND());
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), escrow.DISPUTE_BOND());
        escrow.challengeMilestone(grantId, 1);
        vm.stopPrank();

        vm.prank(RESOLVER);
        escrow.resolveDispute(grantId, 1, approve);
        if (approve) {
            vm.prank(GRANTEE);
            escrow.claimMilestone(grantId, 1);
        } else {
            vm.prank(FUNDER);
            escrow.refundMilestone(grantId, 1);
        }
    }

    function expireAndRefund(uint256 seed) external {
        uint256 grantId = _pendingGrant(seed);
        if (grantId == 0) return;

        vm.warp(uint256(escrow.getMilestone(grantId, 1).submissionDeadline) + 1);
        escrow.markExpiredMilestoneRefundable(grantId, 1);
        vm.prank(FUNDER);
        escrow.refundMilestone(grantId, 1);
    }

    function withdrawFunder() external {
        if (escrow.claimableUSDC(FUNDER) == 0) return;
        vm.prank(FUNDER);
        escrow.withdrawPrincipal(FUNDER);
    }

    function withdrawGrantee() external {
        if (escrow.claimableUSDC(GRANTEE) == 0) return;
        vm.prank(GRANTEE);
        escrow.withdrawPrincipal(GRANTEE);
    }

    function grantCount() external view returns (uint256) {
        return _grantIds.length;
    }

    function _pendingGrant(uint256 seed) private view returns (uint256 grantId) {
        uint256 length = _grantIds.length;
        if (length == 0) return 0;

        grantId = _grantIds[seed % length];
        if (escrow.getGrant(grantId).state != GrantState.Active) return 0;

        MilestoneState state = escrow.getMilestone(grantId, 1).state;
        if (state != MilestoneState.Pending) return 0;
        if (block.timestamp > escrow.getMilestone(grantId, 1).submissionDeadline) return 0;
    }

    function _submitEvidence(uint256 grantId) private {
        vm.prank(GRANTEE);
        escrow.submitEvidence(
            grantId, 1, grantId, keccak256(abi.encode(grantId)), "ipfs://manifest"
        );
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

contract ImpactEscrowInvariantTest is StdInvariant, Test {
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant ADAPTER = address(0xADA7);

    MockUSDC private usdc;
    ImpactEscrow private escrow;
    ImpactEscrowHandler private handler;

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(ADAPTER);
        handler = new ImpactEscrowHandler(usdc, escrow);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.createAndFund.selector;
        selectors[1] = handler.approveAndSettle.selector;
        selectors[2] = handler.manualReviewAndSettle.selector;
        selectors[3] = handler.challengeAndSettle.selector;
        selectors[4] = handler.expireAndRefund.selector;
        selectors[5] = handler.withdrawFunder.selector;
        selectors[6] = handler.withdrawGrantee.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    function invariant_PrincipalIsAlwaysConserved() public view {
        assertEq(
            escrow.totalFundedPrincipal(),
            escrow.totalEscrowedPrincipal() + escrow.totalSettledPrincipal()
        );
    }

    function invariant_EscrowTokenBalanceMatchesLiabilities() public view {
        assertEq(
            usdc.balanceOf(address(escrow)),
            escrow.totalEscrowedPrincipal() + escrow.totalClaimableUSDC()
                + escrow.totalDisputeBonds()
        );
    }

    function invariant_SettledPrincipalNeverExceedsFundedPrincipal() public view {
        assertLe(escrow.totalSettledPrincipal(), escrow.totalFundedPrincipal());
    }
}
