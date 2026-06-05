// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ShannonTestUSDC } from "../src/testnet/ShannonTestUSDC.sol";

contract ShannonTestUSDCTest is Test {
    ShannonTestUSDC private token;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        token = new ShannonTestUSDC();
    }

    function testUsesUSDCStyleDecimalsAndMetadata() public view {
        assertEq(token.name(), "ImpactOS Shannon Test USDC");
        assertEq(token.symbol(), "tUSDC");
        assertEq(token.decimals(), 6);
    }

    function testUsersMintTheirOwnCappedTestBalance() public {
        vm.prank(ALICE);
        token.faucet(1_000e6);
        vm.prank(BOB);
        token.faucet(2_500e6);

        assertEq(token.balanceOf(ALICE), 1_000e6);
        assertEq(token.balanceOf(BOB), 2_500e6);
        assertEq(token.totalSupply(), 3_500e6);
    }

    function testRejectsZeroAndOversizedFaucetRequests() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShannonTestUSDC.FaucetAmountExceeded.selector, 0, token.MAX_FAUCET_AMOUNT()
            )
        );
        token.faucet(0);

        uint256 oversized = token.MAX_FAUCET_AMOUNT() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ShannonTestUSDC.FaucetAmountExceeded.selector, oversized, token.MAX_FAUCET_AMOUNT()
            )
        );
        token.faucet(oversized);
    }
}
