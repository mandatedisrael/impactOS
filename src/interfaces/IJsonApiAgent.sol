// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IJsonApiAgent {
    function fetchString(string calldata url, string calldata selector)
        external
        returns (string memory);

    function fetchUint(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (uint256);

    function fetchInt(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (int256);

    function fetchBool(string calldata url, string calldata selector) external returns (bool);

    function fetchStringArray(string calldata url, string calldata selector)
        external
        returns (string[] memory);

    function fetchUintArray(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (uint256[] memory);
}
