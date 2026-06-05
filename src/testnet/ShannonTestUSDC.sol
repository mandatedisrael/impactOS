// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ShannonTestUSDC is ERC20 {
    uint256 public constant MAX_FAUCET_AMOUNT = 100_000e6;

    error FaucetAmountExceeded(uint256 requested, uint256 maximum);

    constructor() ERC20("ImpactOS Shannon Test USDC", "tUSDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function faucet(uint256 amount) external {
        if (amount == 0 || amount > MAX_FAUCET_AMOUNT) {
            revert FaucetAmountExceeded(amount, MAX_FAUCET_AMOUNT);
        }

        _mint(msg.sender, amount);
    }
}
