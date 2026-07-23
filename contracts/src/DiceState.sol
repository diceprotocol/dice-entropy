// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

import {DiceStructsV2} from "./sdk/DiceStructsV2.sol";

/// @notice Internal storage layout for Dice Protocol.
/// Dice Protocol component.
contract DiceInternalStructs {
    struct State {
        // Admin can set the default provider, change fee, and transfer ownership.
        address admin;
        // Single fee per request in wei. All revenue goes to vault.
        uint128 feeInWei;
        // Total accrued fees currently held in the contract.
        uint128 accruedFeesInWei;
        // Vault address that receives all protocol fees.
        address vault;
        // The protocol sets a provider as default to simplify integration for developers.
        address defaultProvider;
        // Hash table for in-flight requests. Two-level: array + overflow mapping.
        DiceStructsV2.Request[32] requests;
        mapping(bytes32 => DiceStructsV2.Request) requestsOverflow;
        // Mapping from randomness providers to their information.
        mapping(address => DiceStructsV2.ProviderInfo) providers;
        // proposedAdmin is the new admin's address pending acceptance.
        address proposedAdmin;
        // L1 blocks that must elapse before a stuck request can be refunded.
        // On Robinhood/Arbitrum Nitro, block.number is L1 (~12s). Default 6 ≈ ~72s.
        uint64 refundDelayBlocks;
    }
}

/// @notice Storage contract for Dice Protocol.
contract DiceState {
    /// @notice Size of the requests hash table array. Must be a power of 2.
    uint8 public constant NUM_REQUESTS = 32;
    /// @notice Bitmask for the requests array index (NUM_REQUESTS - 1).
    bytes1 public constant NUM_REQUESTS_MASK = 0x1f;
    DiceInternalStructs.State _state;
}
