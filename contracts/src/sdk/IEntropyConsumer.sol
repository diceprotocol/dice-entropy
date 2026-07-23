// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

/// @notice Abstract contract for consuming Dice Protocol randomness.
///         Consumer contracts inherit this and implement entropyCallback().
/// Dice Protocol component.
abstract contract IEntropyConsumer {
    /// @notice Called by the DiceEntropy contract to deliver the random number
    /// @dev Asserts msg.sender is the DiceEntropy contract. Not meant to be overridden.
    function _entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) external {
        address entropy = getEntropy();
        require(entropy != address(0), "Entropy address not set");
        require(msg.sender == entropy, "Only Entropy can call this function");
        entropyCallback(sequence, provider, randomNumber);
    }

    /// @notice Returns the DiceEntropy contract address. Must be implemented by the consumer.
    function getEntropy() internal view virtual returns (address);

    /// @notice Handles the random number. Must be implemented by the consumer.
    function entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) internal virtual;
}
