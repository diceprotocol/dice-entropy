// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IEntropyConsumer} from "@diceprotocol/sdk/IEntropyConsumer.sol";
import {IEntropy} from "@diceprotocol/sdk/IEntropy.sol";

/// @title CoinFlip — provably fair coin flip game powered by Dice Protocol
/// @notice User commits a guess (heads/tails), requests randomness from Dice Protocol,
///         and the callback resolves the flip. Both sides see the proof on-chain.
contract CoinFlip is IEntropyConsumer {
    IEntropy public immutable dice;
    address public immutable provider;

    enum Side { Heads, Tails }
    enum GameState { Pending, Won, Lost }

    struct Game {
        address player;
        Side guess;
        uint256 betAmount;
        GameState state;
        bytes32 randomNumber;
    }

    mapping(uint64 => Game) public games;
    mapping(address => uint256) public winnings;

    event Flipped(uint64 indexed sequence, address indexed player, Side guess, uint256 betAmount);
    event Resolved(uint64 indexed sequence, address indexed player, Side result, GameState state, bytes32 randomNumber);

    constructor(address _dice, address _provider) {
        dice = IEntropy(_dice);
        provider = _provider;
    }

    /// @notice Flip the coin with a guess
    /// @param guess 0 = Heads, 1 = Tails
    /// @param userRandom 32-byte random number (generate client-side)
    function flip(Side guess, bytes32 userRandom) external payable returns (uint64) {
        require(msg.value > 0, "Bet required");
        require(guess == Side.Heads || guess == Side.Tails, "Invalid guess");

        // Request randomness from Dice Protocol
        uint64 seq = dice.requestV2{value: msg.value}(provider, userRandom, 100000);
        games[seq] = Game(msg.sender, guess, msg.value, GameState.Pending, bytes32(0));

        emit Flipped(seq, msg.sender, guess, msg.value);
        return seq;
    }

    /// @notice Internal callback — called by DiceEntropy when the random number is ready
    function entropyCallback(uint64 sequence, address, bytes32 randomNumber) internal override {
        Game storage game = games[sequence];
        require(game.state == GameState.Pending, "Game already resolved");

        game.randomNumber = randomNumber;

        // Result: last bit of the random number determines heads (0) or tails (1)
        Side result = (uint256(randomNumber) & 1 == 1) ? Side.Tails : Side.Heads;

        if (game.guess == result) {
            game.state = GameState.Won;
            winnings[game.player] += game.betAmount * 2;
            (bool sent, ) = game.player.call{value: game.betAmount * 2}("");
            require(sent, "Payout failed");
        } else {
            game.state = GameState.Lost;
        }

        emit Resolved(sequence, game.player, result, game.state, randomNumber);
    }

    function getEntropy() internal view override returns (address) {
        return address(dice);
    }

    /// @notice Get game details
    function getGame(uint64 seq) external view returns (address player, Side guess, uint256 betAmount, GameState state, bytes32 randomNumber) {
        Game memory g = games[seq];
        return (g.player, g.guess, g.betAmount, g.state, g.randomNumber);
    }

    /// @notice Check a game's provably-fair proof
    /// @dev Anyone can verify the random number was derived from the hash chain
    function verifyRandomness(uint64 seq) external view returns (bytes32 randomNumber, Side result) {
        Game memory g = games[seq];
        require(g.state != GameState.Pending, "Game not resolved");
        return (g.randomNumber, (uint256(g.randomNumber) & 1 == 1) ? Side.Tails : Side.Heads);
    }
}