// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ImpactEscrow } from "../src/ImpactEscrow.sol";
import { SomniaVerificationAdapter } from "../src/SomniaVerificationAdapter.sol";
import { IJsonApiAgent } from "../src/interfaces/IJsonApiAgent.sol";
import { MilestoneInput, MilestoneState } from "../src/interfaces/IImpactEscrow.sol";
import { SomniaConfig } from "../src/libraries/SomniaConfig.sol";
import { MockSomniaAgents } from "./mocks/MockSomniaAgents.sol";
import { MockUSDC } from "./mocks/MockUSDC.sol";

contract SomniaVerificationAdapterRequestTest is Test {
    MockUSDC private usdc;
    MockSomniaAgents private agents;
    ImpactEscrow private escrow;
    SomniaVerificationAdapter private adapter;

    address private constant FUNDER = address(0xF00D);
    address private constant GRANTEE = address(0xBEEF);
    address private constant GUARDIAN = address(0xA11CE);
    address private constant RESOLVER = address(0xCAFE);
    address private constant KEEPER = address(0xC0DE);

    function setUp() public {
        usdc = new MockUSDC();
        agents = new MockSomniaAgents();
        escrow = new ImpactEscrow(usdc, GUARDIAN, RESOLVER);
        adapter = new SomniaVerificationAdapter(escrow, agents, GUARDIAN);

        vm.prank(GUARDIAN);
        escrow.configureVerifierAdapter(address(adapter));
        vm.warp(1_750_000_000);
        vm.deal(FUNDER, 10 ether);
    }

    function testQuotesCurrentSomniaObjectiveDeposit() public view {
        assertEq(adapter.quoteObjectiveRequestDeposit(), 0.12 ether);
    }

    function testFunderAddsNativeVerificationReserve() public {
        uint256 grantId = _fundedGrant(false);

        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.25 ether }(grantId, 1);

        assertEq(adapter.verificationReserve(grantId, 1), 0.25 ether);
        assertEq(address(adapter).balance, 0.25 ether);
        assertEq(usdc.balanceOf(address(escrow)), 1_000e6);
    }

    function testRejectsReserveFundingFromNonFunderOrInactiveGrant() public {
        uint256 activeGrantId = _fundedGrant(false);

        vm.deal(KEEPER, 1 ether);
        vm.prank(KEEPER);
        vm.expectRevert(
            abi.encodeWithSelector(SomniaVerificationAdapter.OnlyFunder.selector, KEEPER)
        );
        adapter.fundVerificationReserve{ value: 0.12 ether }(activeGrantId, 1);

        uint256 createdGrantId = _createdGrant();
        vm.prank(FUNDER);
        vm.expectRevert();
        adapter.fundVerificationReserve{ value: 0.12 ether }(createdGrantId, 1);
    }

    function testKeeperSubmitsExactGitHubObjectiveRequest() public {
        uint256 grantId = _fundedGrant(true);

        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.2 ether }(grantId, 1);

        vm.prank(KEEPER);
        uint256 requestId = adapter.requestObjectiveVerification(grantId, 1);

        assertEq(requestId, 1);
        assertEq(adapter.verificationReserve(grantId, 1), 0.08 ether);
        assertEq(agents.lastAgentId(), SomniaConfig.JSON_API_AGENT_ID);
        assertEq(agents.lastRequester(), address(adapter));
        assertEq(agents.lastCallbackAddress(), address(adapter));
        assertEq(agents.lastCallbackSelector(), SomniaVerificationAdapter.handleResponse.selector);
        assertEq(agents.lastValue(), 0.12 ether);
        assertEq(
            agents.lastPayload(),
            abi.encodeWithSelector(
                IJsonApiAgent.fetchBool.selector,
                "https://api.github.com/repos/mandatedisrael/impactOS/pulls/42",
                "merged"
            )
        );

        (uint256 contextGrantId, uint256 contextMilestoneId, uint32 attempt, bool consumed) =
            adapter.requests(requestId);
        assertEq(contextGrantId, grantId);
        assertEq(contextMilestoneId, 1);
        assertEq(attempt, 1);
        assertFalse(consumed);
        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Verifying));
    }

    function testInsufficientReserveDoesNotStartVerification() public {
        uint256 grantId = _fundedGrant(true);
        vm.prank(FUNDER);
        adapter.fundVerificationReserve{ value: 0.1 ether }(grantId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                SomniaVerificationAdapter.InsufficientVerificationReserve.selector,
                0.12 ether,
                0.1 ether
            )
        );
        adapter.requestObjectiveVerification(grantId, 1);

        assertEq(uint256(escrow.getMilestone(grantId, 1).state), uint256(MilestoneState.Pending));
        assertEq(adapter.verificationReserve(grantId, 1), 0.1 ether);
    }

    function testDirectNativeTransfersAreTrackedAsUnallocatedRebates() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(adapter)).call{ value: 0.03 ether }("");
        assertTrue(success);

        assertEq(adapter.unallocatedRebates(), 0.03 ether);
        assertEq(address(adapter).balance, 0.03 ether);
    }

    function _fundedGrant(bool submitEvidence) private returns (uint256 grantId) {
        grantId = _createdGrant();
        usdc.mint(FUNDER, 1_000e6);
        vm.startPrank(FUNDER);
        usdc.approve(address(escrow), 1_000e6);
        escrow.fundGrant(grantId);
        vm.stopPrank();

        if (submitEvidence) {
            vm.prank(GRANTEE);
            escrow.submitEvidence(grantId, 1, 42, keccak256("manifest"), "ipfs://manifest");
        }
    }

    function _createdGrant() private returns (uint256) {
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
