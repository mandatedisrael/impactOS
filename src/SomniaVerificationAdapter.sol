// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IJsonApiAgent } from "./interfaces/IJsonApiAgent.sol";
import {
    GrantState,
    GrantView,
    IImpactEscrow,
    MilestoneState,
    MilestoneView,
    VerificationVerdict
} from "./interfaces/IImpactEscrow.sol";
import {
    AgentRequest,
    AgentResponse,
    ISomniaAgentCallback,
    ISomniaAgents,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";
import { SomniaConfig } from "./libraries/SomniaConfig.sol";

contract SomniaVerificationAdapter is ISomniaAgentCallback, ReentrancyGuard {
    struct RequestContext {
        uint256 grantId;
        uint256 milestoneId;
        uint32 attempt;
        bool consumed;
    }

    IImpactEscrow public immutable escrow;
    ISomniaAgents public immutable platform;
    address public immutable rebateAllocator;

    uint256 public unallocatedRebates;

    mapping(uint256 grantId => mapping(uint256 milestoneId => uint256 balance)) public
        verificationReserve;
    mapping(uint256 requestId => RequestContext context) public requests;

    event VerificationReserveFunded(
        uint256 indexed grantId, uint256 indexed milestoneId, address indexed funder, uint256 amount
    );
    event ObjectiveVerificationRequested(
        uint256 indexed requestId,
        uint256 indexed grantId,
        uint256 indexed milestoneId,
        uint32 attempt,
        uint256 deposit
    );
    event ObjectiveVerificationResolved(
        uint256 indexed requestId, VerificationVerdict verdict, uint256 successfulResponses
    );
    event UnallocatedRebateReceived(address indexed sender, uint256 amount);
    event UnallocatedRebateAssigned(
        uint256 indexed grantId, uint256 indexed milestoneId, uint256 amount
    );
    event VerificationReserveWithdrawn(
        uint256 indexed grantId,
        uint256 indexed milestoneId,
        address indexed recipient,
        uint256 amount
    );

    error InvalidAddress();
    error OnlyFunder(address caller);
    error InactiveGrant(uint256 grantId, GrantState state);
    error EmptyReserveFunding();
    error InsufficientVerificationReserve(uint256 required, uint256 available);
    error OnlyPlatform(address caller);
    error UnknownRequest(uint256 requestId);
    error RequestAlreadyConsumed(uint256 requestId);
    error InvalidCallbackDetails(uint256 requestId);
    error OnlyRebateAllocator(address caller);
    error InsufficientUnallocatedRebate(uint256 required, uint256 available);
    error VerificationReserveStillLocked(uint256 grantId, uint256 milestoneId, MilestoneState state);
    error EmptyVerificationReserve(uint256 grantId, uint256 milestoneId);
    error NativeTransferFailed(address recipient, uint256 amount);

    constructor(IImpactEscrow escrow_, ISomniaAgents platform_, address rebateAllocator_) {
        if (
            address(escrow_) == address(0) || address(platform_) == address(0)
                || rebateAllocator_ == address(0)
        ) {
            revert InvalidAddress();
        }

        escrow = escrow_;
        platform = platform_;
        rebateAllocator = rebateAllocator_;
    }

    function quoteObjectiveRequestDeposit() public view returns (uint256) {
        return SomniaConfig.practicalJsonRequestDeposit(platform.getRequestDeposit());
    }

    function fundVerificationReserve(uint256 grantId, uint256 milestoneId) external payable {
        if (msg.value == 0) revert EmptyReserveFunding();

        GrantView memory grant = escrow.getGrant(grantId);
        if (msg.sender != grant.funder) revert OnlyFunder(msg.sender);
        if (grant.state != GrantState.Active) revert InactiveGrant(grantId, grant.state);
        escrow.getMilestone(grantId, milestoneId);

        verificationReserve[grantId][milestoneId] += msg.value;
        emit VerificationReserveFunded(grantId, milestoneId, msg.sender, msg.value);
    }

    function requestObjectiveVerification(uint256 grantId, uint256 milestoneId)
        external
        nonReentrant
        returns (uint256 requestId)
    {
        MilestoneView memory milestone = escrow.getMilestone(grantId, milestoneId);
        uint256 deposit = quoteObjectiveRequestDeposit();
        uint256 reserve = verificationReserve[grantId][milestoneId];
        if (reserve < deposit) {
            revert InsufficientVerificationReserve(deposit, reserve);
        }

        uint32 attempt = escrow.startVerification(grantId, milestoneId);
        verificationReserve[grantId][milestoneId] = reserve - deposit;

        string memory url = string.concat(
            "https://api.github.com/repos/",
            milestone.repositoryOwner,
            "/",
            milestone.repositoryName,
            "/pulls/",
            _toString(milestone.pullRequestNumber)
        );
        bytes memory payload =
            abi.encodeWithSelector(IJsonApiAgent.fetchBool.selector, url, "merged");

        requestId = platform.createRequest{ value: deposit }(
            SomniaConfig.JSON_API_AGENT_ID, address(this), this.handleResponse.selector, payload
        );
        requests[requestId] = RequestContext({
            grantId: grantId,
            milestoneId: milestoneId,
            attempt: attempt,
            consumed: false
        });

        emit ObjectiveVerificationRequested(requestId, grantId, milestoneId, attempt, deposit);
    }

    function assignUnallocatedRebate(uint256 grantId, uint256 milestoneId, uint256 amount)
        external
    {
        if (msg.sender != rebateAllocator) revert OnlyRebateAllocator(msg.sender);
        uint256 available = unallocatedRebates;
        if (amount == 0 || amount > available) {
            revert InsufficientUnallocatedRebate(amount, available);
        }

        escrow.getMilestone(grantId, milestoneId);
        unallocatedRebates = available - amount;
        verificationReserve[grantId][milestoneId] += amount;

        emit UnallocatedRebateAssigned(grantId, milestoneId, amount);
    }

    function withdrawVerificationReserve(
        uint256 grantId,
        uint256 milestoneId,
        address payable recipient
    ) external nonReentrant {
        GrantView memory grant = escrow.getGrant(grantId);
        if (msg.sender != grant.funder) revert OnlyFunder(msg.sender);
        if (recipient == address(0)) revert NativeTransferFailed(recipient, 0);

        MilestoneView memory milestone = escrow.getMilestone(grantId, milestoneId);
        if (milestone.state != MilestoneState.Paid && milestone.state != MilestoneState.Refunded) {
            revert VerificationReserveStillLocked(grantId, milestoneId, milestone.state);
        }

        uint256 amount = verificationReserve[grantId][milestoneId];
        if (amount == 0) revert EmptyVerificationReserve(grantId, milestoneId);

        verificationReserve[grantId][milestoneId] = 0;
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert NativeTransferFailed(recipient, amount);

        emit VerificationReserveWithdrawn(grantId, milestoneId, recipient, amount);
    }

    function handleResponse(
        uint256 requestId,
        AgentResponse[] memory responses,
        ResponseStatus status,
        AgentRequest memory details
    ) external override {
        if (msg.sender != address(platform)) revert OnlyPlatform(msg.sender);

        RequestContext storage context = requests[requestId];
        if (context.grantId == 0) revert UnknownRequest(requestId);
        if (context.consumed) revert RequestAlreadyConsumed(requestId);
        if (
            details.id != requestId || details.callbackAddress != address(this)
                || details.callbackSelector != this.handleResponse.selector
        ) {
            revert InvalidCallbackDetails(requestId);
        }

        VerificationVerdict verdict;
        uint256 successfulResponses;

        if (status == ResponseStatus.Success) {
            (verdict, successfulResponses) = _objectiveVerdict(responses, details.threshold);
        } else if (status == ResponseStatus.TimedOut) {
            verdict = VerificationVerdict.TimedOut;
        } else {
            verdict = VerificationVerdict.Failed;
        }

        context.consumed = true;
        escrow.recordVerificationVerdict(
            context.grantId, context.milestoneId, context.attempt, verdict
        );

        emit ObjectiveVerificationResolved(requestId, verdict, successfulResponses);
    }

    function _objectiveVerdict(AgentResponse[] memory responses, uint256 threshold)
        private
        pure
        returns (VerificationVerdict verdict, uint256 successfulResponses)
    {
        uint256 mergedCount;

        for (uint256 i; i < responses.length; ++i) {
            if (responses[i].status != ResponseStatus.Success) continue;

            (bool valid, bool merged) = _tryDecodeBool(responses[i].result);
            if (!valid) continue;

            ++successfulResponses;
            if (merged) ++mergedCount;
        }

        if (threshold == 0 || successfulResponses < threshold) {
            return (VerificationVerdict.Failed, successfulResponses);
        }
        if (mergedCount >= threshold) {
            return (VerificationVerdict.Approved, successfulResponses);
        }

        return (VerificationVerdict.Failed, successfulResponses);
    }

    function _tryDecodeBool(bytes memory result) private pure returns (bool valid, bool value) {
        if (result.length != 32) return (false, false);

        uint256 word;
        assembly {
            word := mload(add(result, 0x20))
        }
        if (word > 1) return (false, false);

        return (true, word == 1);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 digits;
        uint256 remaining = value;
        while (remaining != 0) {
            ++digits;
            remaining /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    receive() external payable {
        unallocatedRebates += msg.value;
        emit UnallocatedRebateReceived(msg.sender, msg.value);
    }
}
