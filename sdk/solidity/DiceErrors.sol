// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

/// @notice Error definitions for Dice Protocol.
/// Dice Protocol component.
library DiceErrors {
    // An invariant of the contract failed to hold. This error indicates a software logic bug.
    error AssertionFailure();
    // The requested provider does not exist.
    error NoSuchProvider();
    // The specified request does not exist.
    error NoSuchRequest();
    // The randomness provider is out of committed random numbers.
    // The provider needs to rotate their on-chain commitment to resolve this error.
    error OutOfRandomness();
    // The transaction fee was not sufficient.
    error InsufficientFee();
    // Either the user's or the provider's revealed random values did not match their commitment.
    error IncorrectRevelation();
    // The msg.sender is not allowed to invoke this call.
    error Unauthorized();
    // The blockhash is 0.
    error BlockhashUnavailable();
    // If a request was made using `requestWithCallback`, request should be fulfilled using `revealWithCallback`
    // else if a request was made using `request`, request should be fulfilled using `reveal`
    error InvalidRevealCall();
    // The last random number revealed from the provider is too old. Therefore, too many hashes
    // are required for any new reveal. Please update the currentCommitment before making more requests.
    error LastRevealedTooOld();
    // A more recent commitment is already revealed on-chain.
    error UpdateTooOld();
    // Not enough gas was provided to the function to execute the callback with the desired amount of gas.
    error InsufficientGas();
    // A gas limit value was provided that was greater than the maximum possible limit of 655,350,000.
    error MaxGasLimitExceeded();
    // Refund is not available yet (timeout not elapsed) or the request is not refundable.
    error RefundNotAvailable();
}
