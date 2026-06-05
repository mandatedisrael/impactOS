// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum ConsensusType {
    Majority,
    Threshold
}

enum ResponseStatus {
    None,
    Pending,
    Success,
    Failed,
    TimedOut
}

struct AgentResponse {
    address validator;
    bytes result;
    ResponseStatus status;
    uint256 receipt;
    uint256 timestamp;
    uint256 executionCost;
}

struct AgentRequest {
    uint256 id;
    address requester;
    address callbackAddress;
    bytes4 callbackSelector;
    address[] subcommittee;
    AgentResponse[] responses;
    uint256 responseCount;
    uint256 failureCount;
    uint256 threshold;
    uint256 createdAt;
    uint256 deadline;
    ResponseStatus status;
    ConsensusType consensusType;
    uint256 remainingBudget;
    uint256 perAgentBudget;
}

interface ISomniaAgents {
    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    function createAdvancedRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload,
        uint256 subcommitteeSize,
        uint256 threshold,
        ConsensusType consensusType,
        uint256 timeout
    ) external payable returns (uint256 requestId);

    function getRequest(uint256 requestId) external view returns (AgentRequest memory);

    function hasRequest(uint256 requestId) external view returns (bool);

    function getRequestDeposit() external view returns (uint256);

    function getAdvancedRequestDeposit(uint256 subcommitteeSize) external view returns (uint256);
}

interface ISomniaAgentCallback {
    function handleResponse(
        uint256 requestId,
        AgentResponse[] memory responses,
        ResponseStatus status,
        AgentRequest memory details
    ) external;
}
