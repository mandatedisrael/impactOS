// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    AgentRequest,
    AgentResponse,
    ConsensusType,
    ISomniaAgentCallback,
    ISomniaAgents,
    ResponseStatus
} from "../../src/interfaces/ISomniaAgents.sol";

contract MockSomniaAgents is ISomniaAgents {
    uint256 public nextRequestId = 1;
    uint256 public requestDeposit = 0.03 ether;

    uint256 public lastAgentId;
    address public lastRequester;
    address public lastCallbackAddress;
    bytes4 public lastCallbackSelector;
    bytes public lastPayload;
    uint256 public lastValue;

    mapping(uint256 requestId => AgentRequest request) private _requests;
    mapping(uint256 requestId => bool exists) private _requestExists;

    function setRequestDeposit(uint256 deposit) external {
        requestDeposit = deposit;
    }

    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable override returns (uint256 requestId) {
        requestId = nextRequestId++;

        lastAgentId = agentId;
        lastRequester = msg.sender;
        lastCallbackAddress = callbackAddress;
        lastCallbackSelector = callbackSelector;
        lastPayload = payload;
        lastValue = msg.value;

        AgentRequest storage request = _requests[requestId];
        request.id = requestId;
        request.requester = msg.sender;
        request.callbackAddress = callbackAddress;
        request.callbackSelector = callbackSelector;
        request.threshold = 2;
        request.status = ResponseStatus.Pending;
        request.consensusType = ConsensusType.Majority;
        _requestExists[requestId] = true;
    }

    function createAdvancedRequest(
        uint256,
        address,
        bytes4,
        bytes calldata,
        uint256,
        uint256,
        ConsensusType,
        uint256
    ) external payable override returns (uint256) {
        revert("not implemented");
    }

    function getRequest(uint256 requestId) external view override returns (AgentRequest memory) {
        return _requests[requestId];
    }

    function hasRequest(uint256 requestId) external view override returns (bool) {
        return _requestExists[requestId];
    }

    function getRequestDeposit() external view override returns (uint256) {
        return requestDeposit;
    }

    function getAdvancedRequestDeposit(uint256 subcommitteeSize)
        external
        view
        override
        returns (uint256)
    {
        return requestDeposit * subcommitteeSize;
    }

    function deliverResponse(
        uint256 requestId,
        AgentResponse[] memory responses,
        ResponseStatus status,
        uint256 threshold
    ) external {
        AgentRequest memory request = _requests[requestId];
        request.responses = responses;
        request.responseCount = responses.length;
        request.threshold = threshold;
        request.status = status;

        ISomniaAgentCallback(request.callbackAddress).handleResponse(
            requestId, responses, status, request
        );
    }

    function deliverCustomResponse(
        address callbackAddress,
        uint256 requestId,
        AgentResponse[] memory responses,
        ResponseStatus status,
        AgentRequest memory details
    ) external {
        ISomniaAgentCallback(callbackAddress).handleResponse(requestId, responses, status, details);
    }
}
