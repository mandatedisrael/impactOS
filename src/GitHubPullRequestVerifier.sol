// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IJsonApiAgent } from "./interfaces/IJsonApiAgent.sol";
import {
    AgentRequest,
    AgentResponse,
    ISomniaAgentCallback,
    ISomniaAgents,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";
import { SomniaConfig } from "./libraries/SomniaConfig.sol";

contract GitHubPullRequestVerifier is ISomniaAgentCallback {
    enum VerificationStatus {
        None,
        Pending,
        Merged,
        NotMerged,
        Failed,
        TimedOut
    }

    struct Verification {
        string repositoryOwner;
        string repositoryName;
        uint256 pullRequestNumber;
        VerificationStatus status;
        uint64 requestedAt;
        uint64 resolvedAt;
    }

    ISomniaAgents public immutable platform;
    address public immutable administrator;

    mapping(uint256 requestId => Verification verification) private _verifications;

    event VerificationRequested(
        uint256 indexed requestId,
        string repositoryOwner,
        string repositoryName,
        uint256 indexed pullRequestNumber
    );
    event VerificationResolved(
        uint256 indexed requestId, VerificationStatus status, uint256 successfulResponses
    );
    event NativeFundsWithdrawn(address indexed recipient, uint256 amount);

    error OnlyAdministrator(address caller);
    error OnlyPlatform(address caller);
    error InvalidRepositoryPart(string value);
    error InvalidPullRequestNumber();
    error InsufficientContractBalance(uint256 required, uint256 available);
    error UnknownRequest(uint256 requestId);
    error RequestAlreadyResolved(uint256 requestId);
    error InvalidCallbackDetails(uint256 requestId);
    error NativeTransferFailed(address recipient, uint256 amount);

    modifier onlyAdministrator() {
        if (msg.sender != administrator) revert OnlyAdministrator(msg.sender);
        _;
    }

    constructor(ISomniaAgents platform_, address administrator_) {
        if (address(platform_) == address(0)) revert OnlyPlatform(address(0));
        if (administrator_ == address(0)) revert OnlyAdministrator(address(0));

        platform = platform_;
        administrator = administrator_;
    }

    function quoteRequestDeposit() public view returns (uint256) {
        return SomniaConfig.practicalJsonRequestDeposit(platform.getRequestDeposit());
    }

    function requestMergedStatus(
        string calldata repositoryOwner,
        string calldata repositoryName,
        uint256 pullRequestNumber
    ) external onlyAdministrator returns (uint256 requestId) {
        _validateRepositoryPart(repositoryOwner);
        _validateRepositoryPart(repositoryName);
        if (pullRequestNumber == 0) revert InvalidPullRequestNumber();

        uint256 deposit = quoteRequestDeposit();
        uint256 available = address(this).balance;
        if (available < deposit) revert InsufficientContractBalance(deposit, available);

        string memory url = string.concat(
            "https://api.github.com/repos/",
            repositoryOwner,
            "/",
            repositoryName,
            "/pulls/",
            _toString(pullRequestNumber)
        );
        bytes memory payload =
            abi.encodeWithSelector(IJsonApiAgent.fetchBool.selector, url, "merged");

        requestId = platform.createRequest{ value: deposit }(
            SomniaConfig.JSON_API_AGENT_ID, address(this), this.handleResponse.selector, payload
        );

        _verifications[requestId] = Verification({
            repositoryOwner: repositoryOwner,
            repositoryName: repositoryName,
            pullRequestNumber: pullRequestNumber,
            status: VerificationStatus.Pending,
            requestedAt: uint64(block.timestamp),
            resolvedAt: 0
        });

        emit VerificationRequested(requestId, repositoryOwner, repositoryName, pullRequestNumber);
    }

    function handleResponse(
        uint256 requestId,
        AgentResponse[] memory responses,
        ResponseStatus status,
        AgentRequest memory details
    ) external override {
        if (msg.sender != address(platform)) revert OnlyPlatform(msg.sender);

        Verification storage verification = _verifications[requestId];
        if (verification.status == VerificationStatus.None) revert UnknownRequest(requestId);
        if (verification.status != VerificationStatus.Pending) {
            revert RequestAlreadyResolved(requestId);
        }
        if (
            details.id != requestId || details.callbackAddress != address(this)
                || details.callbackSelector != this.handleResponse.selector
        ) {
            revert InvalidCallbackDetails(requestId);
        }

        VerificationStatus finalStatus;
        uint256 successfulResponses;

        if (status == ResponseStatus.Success) {
            (finalStatus, successfulResponses) = _majorityResult(responses, details.threshold);
        } else if (status == ResponseStatus.TimedOut) {
            finalStatus = VerificationStatus.TimedOut;
        } else {
            finalStatus = VerificationStatus.Failed;
        }

        verification.status = finalStatus;
        verification.resolvedAt = uint64(block.timestamp);

        emit VerificationResolved(requestId, finalStatus, successfulResponses);
    }

    function getVerification(uint256 requestId) external view returns (Verification memory) {
        Verification memory verification = _verifications[requestId];
        if (verification.status == VerificationStatus.None) revert UnknownRequest(requestId);
        return verification;
    }

    function withdrawNative(address payable recipient, uint256 amount) external onlyAdministrator {
        if (recipient == address(0)) revert NativeTransferFailed(recipient, amount);

        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert NativeTransferFailed(recipient, amount);

        emit NativeFundsWithdrawn(recipient, amount);
    }

    function _majorityResult(AgentResponse[] memory responses, uint256 threshold)
        private
        pure
        returns (VerificationStatus status, uint256 successfulResponses)
    {
        uint256 mergedCount;
        uint256 notMergedCount;

        for (uint256 i; i < responses.length; ++i) {
            if (responses[i].status != ResponseStatus.Success) continue;

            (bool valid, bool merged) = _tryDecodeBool(responses[i].result);
            if (!valid) continue;

            ++successfulResponses;
            if (merged) {
                ++mergedCount;
            } else {
                ++notMergedCount;
            }
        }

        if (threshold == 0 || successfulResponses < threshold) {
            return (VerificationStatus.Failed, successfulResponses);
        }
        if (mergedCount >= threshold) {
            return (VerificationStatus.Merged, successfulResponses);
        }
        if (notMergedCount >= threshold) {
            return (VerificationStatus.NotMerged, successfulResponses);
        }

        return (VerificationStatus.Failed, successfulResponses);
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

    function _validateRepositoryPart(string calldata value) private pure {
        bytes calldata characters = bytes(value);
        if (characters.length == 0 || characters.length > 100) {
            revert InvalidRepositoryPart(value);
        }

        for (uint256 i; i < characters.length; ++i) {
            bytes1 character = characters[i];
            bool valid = (character >= 0x30 && character <= 0x39)
                || (character >= 0x41 && character <= 0x5A) || (character >= 0x61 && character <= 0x7A)
                || character == 0x2D || character == 0x2E || character == 0x5F;
            if (!valid) revert InvalidRepositoryPart(value);
        }
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

    receive() external payable { }
}
