// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

/// @title PRNG Contract
/// @notice Pseudorandom number generation utility for Dice Protocol consumers.
/// Dice Protocol component.
contract PRNG {
    bytes32 private seed;
    uint256 private nonce;

    /// @notice Initialize the PRNG with a seed from DiceEntropy
    constructor(bytes32 _seed) {
        seed = _seed;
        nonce = 0;
    }

    /// @notice Set a new seed and reset the nonce
    function setSeed(bytes32 _newSeed) internal {
        seed = _newSeed;
        nonce = 0;
    }

    /// @notice Generate the next random bytes32 value and update the state
    function nextBytes32() internal returns (bytes32) {
        bytes32 result = keccak256(abi.encode(seed, nonce));
        nonce++;
        return result;
    }

    /// @notice Generate a random uint256 value
    function randUint() internal returns (uint256) {
        return uint256(nextBytes32());
    }

    /// @notice Generate a random uint64 value
    function randUint64() internal returns (uint64) {
        return uint64(uint256(nextBytes32()));
    }

    /// @notice Generate a random uint256 value within a specified range [min, max)
    function randUintRange(uint256 min, uint256 max) internal returns (uint256) {
        require(max > min, "Max must be greater than min");
        return (randUint() % (max - min)) + min;
    }

    /// @notice Generate a random permutation of a sequence of given length
    function randomPermutation(uint256 length) internal returns (uint256[] memory) {
        uint256[] memory permutation = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            permutation[i] = i;
        }
        for (uint256 i = 0; i < length; i++) {
            uint256 j = i + (randUint() % (length - i));
            (permutation[i], permutation[j]) = (permutation[j], permutation[i]);
        }
        return permutation;
    }
}
