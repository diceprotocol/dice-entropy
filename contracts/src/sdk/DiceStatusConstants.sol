// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

/// @notice Callback status constants for Dice Protocol requests.
/// Dice Protocol component.
library DiceStatusConstants {
    // Not a request with callback.
    uint8 public constant CALLBACK_NOT_NECESSARY = 0;
    // A request with callback where the callback hasn't been invoked yet.
    uint8 public constant CALLBACK_NOT_STARTED = 1;
    // A request with callback where the callback is currently in flight (reentry guard).
    uint8 public constant CALLBACK_IN_PROGRESS = 2;
    // A request with callback where the callback has been invoked and failed.
    uint8 public constant CALLBACK_FAILED = 3;
}
