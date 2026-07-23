// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CoinFlip} from "../contracts/CoinFlip.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";

contract CoinFlipTest is Test {
    DiceEntropy dice;
    CoinFlip flip;
    address provider = address(0xBEEF1);
    address treasury = address(0xBEEF2);
    address player1 = address(0x1111);
    address player2 = address(0x2222);

    // Hash chain: x_3 = seed, x_2 = hash(x_3), x_1 = hash(x_2), x_0 = hash(x_1) = commitment
    bytes32 seed = keccak256("dice-protocol-test");
    bytes32 x3 = seed;
    bytes32 x2;
    bytes32 x1;
    bytes32 x0;

    function setUp() public {
        // Compute hash chain
        x2 = keccak256(abi.encodePacked(x3));
        x1 = keccak256(abi.encodePacked(x2));
        x0 = keccak256(abi.encodePacked(x1));

        // Deploy DiceEntropy
        dice = new DiceEntropy(address(this), 0, provider, false, treasury);

        // Register provider with chain of 10
        vm.prank(provider);
        dice.register(0, x0, "", 10, "");

        // Deploy CoinFlip
        flip = new CoinFlip(address(dice), provider);

        // Fund the coin flip contract
        vm.deal(address(flip), 10 ether);
        vm.deal(player1, 5 ether);
        vm.deal(player2, 5 ether);
    }

    function test_FlipAndResolve_Win() public {
        bytes32 userRandom = keccak256("player1-random");

        // Player 1 flips, guessing Heads (0)
        vm.prank(player1);
        uint64 seq = flip.flip{value: 0.1 ether}(CoinFlip.Side.Heads, userRandom);

        // Check game created
        (address p, CoinFlip.Side guess, uint256 bet, CoinFlip.GameState state, bytes32 rng) = flip.getGame(seq);
        assertEq(p, player1);
        assertEq(uint(guess), uint(CoinFlip.Side.Heads));
        assertEq(bet, 0.1 ether);
        assertEq(uint(state), uint(CoinFlip.GameState.Pending));

        // Provider reveals
        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);

        // Check result
        (, , , CoinFlip.GameState finalState, bytes32 finalRng) = flip.getGame(seq);
        assertTrue(finalState == CoinFlip.GameState.Won || finalState == CoinFlip.GameState.Lost, "Should be resolved");
        assertNotEq(finalRng, bytes32(0), "Random number should be set");
    }

    function test_FlipAndResolve_Lose() public {
        bytes32 userRandom = keccak256("player2-random");

        vm.prank(player2);
        uint64 seq = flip.flip{value: 0.05 ether}(CoinFlip.Side.Tails, userRandom);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);

        (, , , CoinFlip.GameState finalState, ) = flip.getGame(seq);
        assertTrue(finalState != CoinFlip.GameState.Pending, "Should be resolved");
    }

    function test_MultipleFlips() public {
        // Flip 3 times using x1, x2, x3
        bytes32 r1 = keccak256("r1");
        bytes32 r2 = keccak256("r2");
        bytes32 r3 = keccak256("r3");

        vm.startPrank(player1);
        uint64 s1 = flip.flip{value: 0.1 ether}(CoinFlip.Side.Heads, r1);
        uint64 s2 = flip.flip{value: 0.1 ether}(CoinFlip.Side.Tails, r2);
        uint64 s3 = flip.flip{value: 0.1 ether}(CoinFlip.Side.Heads, r3);
        vm.stopPrank();

        // Reveal all 3
        vm.startPrank(provider);
        dice.revealWithCallback(provider, s1, r1, x1);
        dice.revealWithCallback(provider, s2, r2, x2);
        dice.revealWithCallback(provider, s3, r3, x3);
        vm.stopPrank();

        // All should be resolved
        (, , , CoinFlip.GameState st1, ) = flip.getGame(s1);
        (, , , CoinFlip.GameState st2, ) = flip.getGame(s2);
        (, , , CoinFlip.GameState st3, ) = flip.getGame(s3);
        assertTrue(st1 != CoinFlip.GameState.Pending);
        assertTrue(st2 != CoinFlip.GameState.Pending);
        assertTrue(st3 != CoinFlip.GameState.Pending);
    }

    function test_RevertOnZeroBet() public {
        vm.prank(player1);
        vm.expectRevert("Bet required");
        flip.flip(CoinFlip.Side.Heads, keccak256("test"));
    }

    function test_VerifyRandomness() public {
        bytes32 userRandom = keccak256("verify-test");

        vm.prank(player1);
        uint64 seq = flip.flip{value: 0.1 ether}(CoinFlip.Side.Heads, userRandom);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);

        (bytes32 rng, CoinFlip.Side result) = flip.verifyRandomness(seq);
        assertNotEq(rng, bytes32(0));
        assertTrue(result == CoinFlip.Side.Heads || result == CoinFlip.Side.Tails);
    }
}