// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import {
    GrantState,
    GrantView,
    MilestoneInput,
    MilestoneState,
    MilestoneView
} from "../src/interfaces/IImpactEscrow.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowCreationTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.warp(1_750_000_000);
    }

    function testCreatesGrantWithFrozenMilestones() public {
        MilestoneInput[] memory inputs = new MilestoneInput[](2);
        inputs[0] = _input(1_000e6, "main", 7 days);
        inputs[1] = _input(2_000e6, "release/v1", 3 days);

        vm.prank(FUNDER);
        uint256 grantId = escrow.createGrant(GRANTEE, inputs);

        assertEq(grantId, 1);
        assertEq(escrow.nextGrantId(), 2);

        GrantView memory grant = escrow.getGrant(grantId);
        assertEq(grant.funder, FUNDER);
        assertEq(grant.grantee, GRANTEE);
        assertEq(uint256(grant.state), uint256(GrantState.Created));
        assertEq(grant.milestoneCount, 2);
        assertEq(grant.createdAt, 1_750_000_000);
        assertEq(grant.totalPrincipal, 3_000e6);
        assertEq(grant.remainingPrincipal, 0);

        MilestoneView memory first = escrow.getMilestone(grantId, 1);
        assertEq(first.amount, 1_000e6);
        assertEq(uint256(first.state), uint256(MilestoneState.Pending));
        assertEq(first.repositoryOwner, "mandatedisrael");
        assertEq(first.repositoryName, "impactOS");
        assertEq(first.expectedBaseBranch, "main");
        assertEq(first.acceptanceCriteriaHash, keccak256("criteria"));
        assertEq(first.acceptanceCriteriaURI, "ipfs://criteria");
        assertEq(first.submissionDeadline, 1_750_000_000 + 30 days);
        assertEq(first.challengePeriod, 7 days);

        MilestoneView memory second = escrow.getMilestone(grantId, 2);
        assertEq(second.amount, 2_000e6);
        assertEq(second.expectedBaseBranch, "release/v1");
        assertEq(second.challengePeriod, 3 days);
    }

    function testAssignsSequentialGrantIds() public {
        MilestoneInput[] memory inputs = _singleInput();

        vm.startPrank(FUNDER);
        assertEq(escrow.createGrant(GRANTEE, inputs), 1);
        assertEq(escrow.createGrant(GRANTEE, inputs), 2);
        vm.stopPrank();
    }

    function testFunderCancelsCreatedGrant() public {
        uint256 grantId = _createGrant();

        vm.prank(FUNDER);
        escrow.cancelGrant(grantId);

        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Cancelled));

        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, grantId, GrantState.Cancelled
            )
        );
        escrow.cancelGrant(grantId);
    }

    function testRejectsCancellationByNonFunder() public {
        uint256 grantId = _createGrant();

        vm.prank(GRANTEE);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyFunder.selector, GRANTEE));
        escrow.cancelGrant(grantId);
    }

    function testRejectsInvalidParticipantsAndMilestoneCount() public {
        MilestoneInput[] memory noMilestones = new MilestoneInput[](0);

        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidGrantee.selector, address(0)));
        escrow.createGrant(address(0), _singleInput());

        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidMilestoneCount.selector, 0));
        escrow.createGrant(GRANTEE, noMilestones);
    }

    function testRejectsInvalidMilestoneTerms() public {
        MilestoneInput[] memory inputs = _singleInput();
        inputs[0].amount = 0;
        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidMilestoneAmount.selector, 1));
        escrow.createGrant(GRANTEE, inputs);

        inputs = _singleInput();
        inputs[0].submissionDeadline = uint64(block.timestamp);
        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidSubmissionDeadline.selector, 1, uint64(block.timestamp)
            )
        );
        escrow.createGrant(GRANTEE, inputs);

        inputs = _singleInput();
        inputs[0].challengePeriod = 1 minutes;
        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.InvalidChallengePeriod.selector, 1, 1 minutes)
        );
        escrow.createGrant(GRANTEE, inputs);

        inputs = _singleInput();
        inputs[0].acceptanceCriteriaHash = bytes32(0);
        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidAcceptanceCriteria.selector, 1));
        escrow.createGrant(GRANTEE, inputs);
    }

    function testRejectsUnsafeRepositoryAndEmptyURI() public {
        MilestoneInput[] memory inputs = _singleInput();
        inputs[0].repositoryName = "impact OS";
        vm.prank(FUNDER);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.InvalidRepositoryPart.selector, 1, "impact OS")
        );
        escrow.createGrant(GRANTEE, inputs);

        inputs = _singleInput();
        inputs[0].acceptanceCriteriaURI = "";
        vm.prank(FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.InvalidURI.selector, 1, ""));
        escrow.createGrant(GRANTEE, inputs);
    }

    function testRejectsUnknownGrantAndMilestone() public {
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.UnknownGrant.selector, 99));
        escrow.getGrant(99);

        uint256 grantId = _createGrant();
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.UnknownMilestone.selector, grantId, 2));
        escrow.getMilestone(grantId, 2);
    }

    function _createGrant() private returns (uint256) {
        vm.prank(FUNDER);
        return escrow.createGrant(GRANTEE, _singleInput());
    }

    function _singleInput() private view returns (MilestoneInput[] memory inputs) {
        inputs = new MilestoneInput[](1);
        inputs[0] = _input(1_000e6, "main", 2 days);
    }

    function _input(uint256 amount, string memory baseBranch, uint64 challengePeriod)
        private
        view
        returns (MilestoneInput memory)
    {
        return MilestoneInput({
            amount: amount,
            repositoryOwner: "mandatedisrael",
            repositoryName: "impactOS",
            expectedBaseBranch: baseBranch,
            acceptanceCriteriaHash: keccak256("criteria"),
            acceptanceCriteriaURI: "ipfs://criteria",
            submissionDeadline: uint64(block.timestamp + 30 days),
            challengePeriod: challengePeriod
        });
    }
}
