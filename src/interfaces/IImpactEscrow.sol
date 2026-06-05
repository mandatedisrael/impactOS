// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum GrantState {
    None,
    Created,
    Active,
    Completed,
    Cancelled
}

enum MilestoneState {
    None,
    Pending,
    Verifying,
    ProposedApproval,
    ManualReview,
    Disputed,
    Claimable,
    Paid,
    Refundable,
    Refunded
}

enum VerificationVerdict {
    None,
    Approved,
    ManualReview,
    Failed,
    TimedOut
}

struct MilestoneInput {
    uint256 amount;
    string repositoryOwner;
    string repositoryName;
    string expectedBaseBranch;
    bytes32 acceptanceCriteriaHash;
    string acceptanceCriteriaURI;
    uint64 submissionDeadline;
    uint64 challengePeriod;
}

struct GrantView {
    address funder;
    address grantee;
    GrantState state;
    uint32 milestoneCount;
    uint64 createdAt;
    uint256 totalPrincipal;
    uint256 remainingPrincipal;
}

struct MilestoneView {
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

interface IImpactEscrow {
    function getGrant(uint256 grantId) external view returns (GrantView memory);

    function getMilestone(uint256 grantId, uint256 milestoneId)
        external
        view
        returns (MilestoneView memory);

    function startVerification(uint256 grantId, uint256 milestoneId)
        external
        returns (uint32 attempt);

    function recordVerificationVerdict(
        uint256 grantId,
        uint256 milestoneId,
        uint32 attempt,
        VerificationVerdict verdict
    ) external;
}
