// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeOnTransferToken is ERC20 {
    uint256 private constant FEE_BASIS_POINTS = 100;

    constructor() ERC20("Fee Token", "FEE") { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = (value * FEE_BASIS_POINTS) / 10_000;
        super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}
