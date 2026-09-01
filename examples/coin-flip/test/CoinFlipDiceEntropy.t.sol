// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoinFlip} from "../contracts/CoinFlip.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";
import {DiceErrors} from "@diceprotocol/sdk/solidity/DiceErrors.sol";

/// @notice Compiles CoinFlip against in-repo DiceEntropy (9-arg constructor).
contract CoinFlipDiceEntropyTest is Test {
    DiceEntropy internal dice;
    CoinFlip internal flip;

    address internal admin = address(0xA11CE);
    address internal provider = address(0xBEEF4);
    address internal vault = address(0xBEEF5);
    address internal player = address(0xB0B);

    uint128 internal constant FEE = 0.000025 ether;
    uint256 internal constant WAGER = 0.001 ether;

    bytes32 internal x0;
    bytes32 internal x1;
    bytes32 internal x2;
    bytes32 internal x3;

    function setUp() public {
        x3 = keccak256("coin-flip-example");
        x2 = keccak256(bytes.concat(x3));
        x1 = keccak256(bytes.concat(x2));
        x0 = keccak256(bytes.concat(x1));

        dice = new DiceEntropy(admin, FEE, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        vm.prank(admin);
        dice.registerFor(provider, 0, x0, "", 8, "");
        vm.prank(provider);
        dice.setDefaultGasLimit(200_000);

        vm.prank(admin);
        flip = new CoinFlip(address(dice), provider);

        vm.deal(admin, 20 ether);
        vm.deal(player, 5 ether);
        vm.prank(admin);
        (bool ok,) = address(flip).call{value: 5 ether}("");
        require(ok, "fund");
    }

    function test_ExactFeeForwardedWagerEscrowed() public {
        uint256 houseBefore = address(flip).balance;
        bytes32 userRandom = keccak256("player-random");
        uint256 total = FEE + WAGER;

        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, userRandom, WAGER);

        (, , uint256 wager, CoinFlip.GameState state,) = flip.getGame(seq);
        assertEq(wager, WAGER);
        assertEq(uint256(state), uint256(CoinFlip.GameState.Pending));
        assertEq(address(flip).balance, houseBefore + WAGER);
        assertEq(dice.getAccruedFees(), FEE);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);

        (, , , CoinFlip.GameState finalState, bytes32 rng) = flip.getGame(seq);
        assertTrue(
            finalState == CoinFlip.GameState.Won || finalState == CoinFlip.GameState.Lost
        );
        assertTrue(rng != bytes32(0));

        if (finalState == CoinFlip.GameState.Won) {
            assertEq(flip.pendingPayouts(player), 2 * WAGER);
            vm.prank(player);
            flip.withdraw();
            assertEq(flip.pendingPayouts(player), 0);
        } else {
            assertEq(flip.pendingPayouts(player), 0);
        }
    }

    function test_WrongFeeRevertsAtOracle() public {
        vm.prank(player);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoinFlip.ExactFeePlusWagerRequired.selector, FEE + WAGER, WAGER
            )
        );
        flip.flip{value: WAGER}(CoinFlip.Side.Heads, keccak256("x"), WAGER);
    }
}
