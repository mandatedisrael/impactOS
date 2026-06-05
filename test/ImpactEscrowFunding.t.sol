// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { GrantState, MilestoneInput } from "../src/interfaces/IImpactEscrow.sol";
import { FeeOnTransferToken } from "./mocks/FeeOnTransferToken.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract ImpactEscrowFundingTest is Test {
    MockUSDC private usdc;
    ImpactEscrow private escrow;

    address private constant FUNDER = address(0xF00D);
    address private constant OTHER_FUNDER = address(0xD00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        vm.warp(1_750_000_000);
    }

    function testFunderActivatesGrantWithExactPrincipal() public {
        uint256 grantId = _createGrant(1_000e6);
        usdc.mint(FUNDER, 1_000e6);

        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(FUNDER), 0);
        assertEq(usdc.balanceOf(address(escrow)), 1_000e6);
        assertEq(escrow.totalEscrowedPrincipal(), 1_000e6);
        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Active));
        assertEq(escrow.getGrant(grantId).remainingPrincipal, 1_000e6);
    }

    function testTracksPrincipalAcrossMultipleFundedGrants() public {
        uint256 firstGrantId = _createGrant(1_000e6);

        vm.prank(OTHER_FUNDER);
        uint256 secondGrantId = escrow.createGrant(GRANTEE, _singleInput(2_500e6));

        usdc.mint(FUNDER, 1_000e6);
        usdc.mint(OTHER_FUNDER, 2_500e6);

        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        escrow.fundGrant(firstGrantId);
        vm.stopPrank();

        vm.startPrank(OTHER_FUNDER);
        usdc.approve(address(escrow), 2_500e6);
        escrow.fundGrant(secondGrantId);
        vm.stopPrank();

        assertEq(escrow.totalEscrowedPrincipal(), 3_500e6);
        assertEq(usdc.balanceOf(address(escrow)), 3_500e6);
    }

    function testRejectsFundingByAnyoneExceptOriginalFunder() public {
        uint256 grantId = _createGrant(1_000e6);

        vm.prank(OTHER_FUNDER);
        vm.expectRevert(abi.encodeWithSelector(ImpactEscrow.OnlyFunder.selector, OTHER_FUNDER));
        escrow.fundGrant(grantId);
    }

    function testRejectsDuplicateAndCancelledFunding() public {
        uint256 fundedGrantId = _createGrant(1_000e6);
        usdc.mint(FUNDER, 2_000e6);

        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 2_000e6);
        escrow.fundGrant(fundedGrantId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, fundedGrantId, GrantState.Active
            )
        );
        escrow.fundGrant(fundedGrantId);
        vm.stopPrank();

        uint256 cancelledGrantId = _createGrant(1_000e6);
        vm.startPrank(FUNDER);
        escrow.cancelGrant(cancelledGrantId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ImpactEscrow.InvalidGrantState.selector, cancelledGrantId, GrantState.Cancelled
            )
        );
        escrow.fundGrant(cancelledGrantId);
        vm.stopPrank();
    }

    function testMissingAllowanceLeavesGrantUnfunded() public {
        uint256 grantId = _createGrant(1_000e6);
        usdc.mint(FUNDER, 1_000e6);

        vm.prank(FUNDER);
        vm.expectRevert();
        escrow.fundGrant(grantId);

        assertEq(uint256(escrow.getGrant(grantId).state), uint256(GrantState.Created));
        assertEq(escrow.getGrant(grantId).remainingPrincipal, 0);
        assertEq(escrow.totalEscrowedPrincipal(), 0);
    }

    function testRejectsFeeOnTransferPrincipalAndRollsBack() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        ImpactEscrow feeEscrow = new ImpactEscrow(feeToken, GUARDIAN, RESOLVER);

        vm.prank(FUNDER);
        uint256 grantId = feeEscrow.createGrant(GRANTEE, _singleInput(1_000e6));

        feeToken.mint(FUNDER, 1_000e6);
        vm.startPrank(FUNDER);
        feeToken.approve(address(feeEscrow), 1_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(ImpactEscrow.IncorrectTokenAmount.selector, 1_000e6, 990e6)
        );
        feeEscrow.fundGrant(grantId);
        vm.stopPrank();

        assertEq(feeToken.balanceOf(FUNDER), 1_000e6);
        assertEq(feeToken.balanceOf(address(feeEscrow)), 0);
        assertEq(uint256(feeEscrow.getGrant(grantId).state), uint256(GrantState.Created));
        assertEq(feeEscrow.totalEscrowedPrincipal(), 0);
    }

    function _createGrant(uint256 amount) private returns (uint256) {
        vm.prank(FUNDER);
        return escrow.createGrant(GRANTEE, _singleInput(amount));
    }

    function _singleInput(uint256 amount) private view returns (MilestoneInput[] memory inputs) {
        inputs = new MilestoneInput[](1);
        inputs[0] = MilestoneInput({
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
