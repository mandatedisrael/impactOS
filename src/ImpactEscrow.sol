// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    GrantState,
    GrantView,
    MilestoneInput,
    MilestoneState,
    MilestoneView
} from "./interfaces/IImpactEscrow.sol";

contract ImpactEscrow is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_MILESTONES = 20;
    uint256 public constant MAX_REPOSITORY_PART_LENGTH = 100;
    uint256 public constant MAX_URI_LENGTH = 256;
    uint64 public constant MIN_CHALLENGE_PERIOD = 1 hours;
    uint64 public constant MAX_CHALLENGE_PERIOD = 30 days;

    struct Grant {
        address funder;
        address grantee;
        GrantState state;
        uint32 milestoneCount;
        uint64 createdAt;
        uint256 totalPrincipal;
        uint256 remainingPrincipal;
    }

    struct Milestone {
        uint256 amount;
        MilestoneState state;
        string repositoryOwner;
        string repositoryName;
        string expectedBaseBranch;
        bytes32 acceptanceCriteriaHash;
        string acceptanceCriteriaURI;
        uint64 submissionDeadline;
        uint64 challengePeriod;
        uint64 submittedAt;
        uint64 challengeDeadline;
        uint32 verificationAttempt;
        uint256 pullRequestNumber;
        bytes32 evidenceManifestHash;
        string evidenceURI;
    }

    IERC20 public immutable principalToken;
    address public immutable guardian;
    address public immutable resolver;

    uint256 public nextGrantId = 1;
    uint256 public totalEscrowedPrincipal;

    mapping(uint256 grantId => Grant grant) private _grants;
    mapping(uint256 grantId => mapping(uint256 milestoneId => Milestone milestone)) private
        _milestones;

    event GrantCreated(
        uint256 indexed grantId,
        address indexed funder,
        address indexed grantee,
        uint256 totalPrincipal,
        uint256 milestoneCount
    );
    event MilestoneConfigured(
        uint256 indexed grantId,
        uint256 indexed milestoneId,
        uint256 amount,
        bytes32 acceptanceCriteriaHash,
        uint64 submissionDeadline,
        uint64 challengePeriod
    );
    event GrantCancelled(uint256 indexed grantId);
    event GrantFunded(uint256 indexed grantId, address indexed funder, uint256 amount);

    error InvalidAddress();
    error InvalidGrantee(address grantee);
    error InvalidMilestoneCount(uint256 count);
    error InvalidMilestoneAmount(uint256 milestoneId);
    error InvalidSubmissionDeadline(uint256 milestoneId, uint64 deadline);
    error InvalidChallengePeriod(uint256 milestoneId, uint64 challengePeriod);
    error InvalidAcceptanceCriteria(uint256 milestoneId);
    error InvalidRepositoryPart(uint256 milestoneId, string value);
    error InvalidURI(uint256 milestoneId, string value);
    error UnknownGrant(uint256 grantId);
    error UnknownMilestone(uint256 grantId, uint256 milestoneId);
    error OnlyFunder(address caller);
    error InvalidGrantState(uint256 grantId, GrantState current);
    error IncorrectTokenAmount(uint256 expected, uint256 received);

    constructor(IERC20 principalToken_, address guardian_, address resolver_) {
        if (
            address(principalToken_) == address(0) || guardian_ == address(0)
                || resolver_ == address(0)
        ) {
            revert InvalidAddress();
        }

        principalToken = principalToken_;
        guardian = guardian_;
        resolver = resolver_;
    }

    function createGrant(address grantee, MilestoneInput[] calldata milestoneInputs)
        external
        whenNotPaused
        returns (uint256 grantId)
    {
        if (grantee == address(0) || grantee == msg.sender) revert InvalidGrantee(grantee);

        uint256 milestoneCount = milestoneInputs.length;
        if (milestoneCount == 0 || milestoneCount > MAX_MILESTONES) {
            revert InvalidMilestoneCount(milestoneCount);
        }

        grantId = nextGrantId++;
        uint256 totalPrincipal;

        for (uint256 i; i < milestoneCount; ++i) {
            uint256 milestoneId = i + 1;
            MilestoneInput calldata input = milestoneInputs[i];
            _validateMilestoneInput(milestoneId, input);

            totalPrincipal += input.amount;
            _milestones[grantId][milestoneId] = Milestone({
                amount: input.amount,
                state: MilestoneState.Pending,
                repositoryOwner: input.repositoryOwner,
                repositoryName: input.repositoryName,
                expectedBaseBranch: input.expectedBaseBranch,
                acceptanceCriteriaHash: input.acceptanceCriteriaHash,
                acceptanceCriteriaURI: input.acceptanceCriteriaURI,
                submissionDeadline: input.submissionDeadline,
                challengePeriod: input.challengePeriod,
                submittedAt: 0,
                challengeDeadline: 0,
                verificationAttempt: 0,
                pullRequestNumber: 0,
                evidenceManifestHash: bytes32(0),
                evidenceURI: ""
            });

            emit MilestoneConfigured(
                grantId,
                milestoneId,
                input.amount,
                input.acceptanceCriteriaHash,
                input.submissionDeadline,
                input.challengePeriod
            );
        }

        _grants[grantId] = Grant({
            funder: msg.sender,
            grantee: grantee,
            state: GrantState.Created,
            milestoneCount: uint32(milestoneCount),
            createdAt: uint64(block.timestamp),
            totalPrincipal: totalPrincipal,
            remainingPrincipal: 0
        });

        emit GrantCreated(grantId, msg.sender, grantee, totalPrincipal, milestoneCount);
    }

    function cancelGrant(uint256 grantId) external {
        Grant storage grant = _getGrant(grantId);
        if (msg.sender != grant.funder) revert OnlyFunder(msg.sender);
        if (grant.state != GrantState.Created) revert InvalidGrantState(grantId, grant.state);

        grant.state = GrantState.Cancelled;
        emit GrantCancelled(grantId);
    }

    function fundGrant(uint256 grantId) external whenNotPaused nonReentrant {
        Grant storage grant = _getGrant(grantId);
        if (msg.sender != grant.funder) revert OnlyFunder(msg.sender);
        if (grant.state != GrantState.Created) revert InvalidGrantState(grantId, grant.state);

        uint256 amount = grant.totalPrincipal;
        uint256 balanceBefore = principalToken.balanceOf(address(this));

        grant.state = GrantState.Active;
        grant.remainingPrincipal = amount;
        totalEscrowedPrincipal += amount;

        principalToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 received = principalToken.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert IncorrectTokenAmount(amount, received);

        emit GrantFunded(grantId, msg.sender, amount);
    }

    function getGrant(uint256 grantId) external view returns (GrantView memory) {
        Grant storage grant = _getGrant(grantId);
        return GrantView({
            funder: grant.funder,
            grantee: grant.grantee,
            state: grant.state,
            milestoneCount: grant.milestoneCount,
            createdAt: grant.createdAt,
            totalPrincipal: grant.totalPrincipal,
            remainingPrincipal: grant.remainingPrincipal
        });
    }

    function getMilestone(uint256 grantId, uint256 milestoneId)
        external
        view
        returns (MilestoneView memory)
    {
        _getGrant(grantId);
        Milestone storage milestone = _getMilestone(grantId, milestoneId);

        return MilestoneView({
            amount: milestone.amount,
            state: milestone.state,
            repositoryOwner: milestone.repositoryOwner,
            repositoryName: milestone.repositoryName,
            expectedBaseBranch: milestone.expectedBaseBranch,
            acceptanceCriteriaHash: milestone.acceptanceCriteriaHash,
            acceptanceCriteriaURI: milestone.acceptanceCriteriaURI,
            submissionDeadline: milestone.submissionDeadline,
            challengePeriod: milestone.challengePeriod,
            submittedAt: milestone.submittedAt,
            challengeDeadline: milestone.challengeDeadline,
            verificationAttempt: milestone.verificationAttempt,
            pullRequestNumber: milestone.pullRequestNumber,
            evidenceManifestHash: milestone.evidenceManifestHash,
            evidenceURI: milestone.evidenceURI
        });
    }

    function _validateMilestoneInput(uint256 milestoneId, MilestoneInput calldata input)
        private
        view
    {
        if (input.amount == 0) revert InvalidMilestoneAmount(milestoneId);
        if (input.submissionDeadline <= block.timestamp) {
            revert InvalidSubmissionDeadline(milestoneId, input.submissionDeadline);
        }
        if (
            input.challengePeriod < MIN_CHALLENGE_PERIOD
                || input.challengePeriod > MAX_CHALLENGE_PERIOD
        ) {
            revert InvalidChallengePeriod(milestoneId, input.challengePeriod);
        }
        if (input.acceptanceCriteriaHash == bytes32(0)) {
            revert InvalidAcceptanceCriteria(milestoneId);
        }

        _validateRepositoryPart(milestoneId, input.repositoryOwner);
        _validateRepositoryPart(milestoneId, input.repositoryName);
        _validateRepositoryPart(milestoneId, input.expectedBaseBranch);
        _validateURI(milestoneId, input.acceptanceCriteriaURI);
    }

    function _validateRepositoryPart(uint256 milestoneId, string calldata value) private pure {
        bytes calldata characters = bytes(value);
        if (characters.length == 0 || characters.length > MAX_REPOSITORY_PART_LENGTH) {
            revert InvalidRepositoryPart(milestoneId, value);
        }

        for (uint256 i; i < characters.length; ++i) {
            bytes1 character = characters[i];
            bool valid = (character >= 0x30 && character <= 0x39)
                || (character >= 0x41 && character <= 0x5A) || (character >= 0x61 && character <= 0x7A)
                || character == 0x2D || character == 0x2E || character == 0x2F || character == 0x5F;
            if (!valid) revert InvalidRepositoryPart(milestoneId, value);
        }
    }

    function _validateURI(uint256 milestoneId, string calldata value) private pure {
        uint256 length = bytes(value).length;
        if (length == 0 || length > MAX_URI_LENGTH) revert InvalidURI(milestoneId, value);
    }

    function _getGrant(uint256 grantId) private view returns (Grant storage grant) {
        grant = _grants[grantId];
        if (grant.state == GrantState.None) revert UnknownGrant(grantId);
    }

    function _getMilestone(uint256 grantId, uint256 milestoneId)
        private
        view
        returns (Milestone storage milestone)
    {
        milestone = _milestones[grantId][milestoneId];
        if (milestone.state == MilestoneState.None) {
            revert UnknownMilestone(grantId, milestoneId);
        }
    }
}
