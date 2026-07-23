// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

/// @notice Struct definitions for Dice Protocol V2 storage.
/// Dice Protocol component.
contract DiceStructsV2 {
    struct ProviderInfo {
        uint128 feeInWei;
        uint128 accruedFeesInWei;
        // The commitment that the provider posted to the blockchain, and the sequence number
        // where they committed to this. This value is not advanced after the provider commits,
        // and instead is stored to help providers track where they are in the hash chain.
        bytes32 originalCommitment;
        uint64 originalCommitmentSequenceNumber;
        // Metadata for the current commitment. Providers may optionally use this field to help
        // manage rotations (i.e., to pick the sequence number from the correct hash chain).
        bytes commitmentMetadata;
        // Optional URI where clients can retrieve revelations for the provider.
        bytes uri;
        // The first sequence number that is *not* included in the current commitment (exclusive end).
        // The contract maintains the invariant that sequenceNumber <= endSequenceNumber.
        // If sequenceNumber == endSequenceNumber, the provider must rotate their commitment.
        uint64 endSequenceNumber;
        // The sequence number that will be assigned to the next inbound user request.
        uint64 sequenceNumber;
        // The current commitment represents an index/value in the provider's hash chain.
        // These values are used to verify requests for future sequence numbers.
        // currentCommitmentSequenceNumber < sequenceNumber.
        bytes32 currentCommitment;
        uint64 currentCommitmentSequenceNumber;
        // An address that is authorized to set / withdraw fees on behalf of this provider.
        address feeManager;
        // Maximum number of hashes to record in a request.
        uint32 maxNumHashes;
        // Default gas limit to use for callbacks.
        uint32 defaultGasLimit;
    }

    struct Request {
        // Storage slot 1 //
        address provider;
        uint64 sequenceNumber;
        // The number of hashes required to verify the provider revelation.
        uint32 numHashes;
        // Storage slot 2 //
        // The commitment is keccak256(userCommitment, providerCommitment).
        // Storing the hash instead of both saves 20k gas by eliminating 1 store.
        bytes32 commitment;
        // Storage slot 3 //
        // The number of the block where this request was created.
        uint64 blockNumber;
        // The address that requested this random number.
        address requester;
        // If true, incorporate the blockhash of blockNumber into the generated random value.
        bool useBlockhash;
        // Status flag for requests with callbacks. See DiceStatusConstants for possible values.
        uint8 callbackStatus;
        // The gasLimit in units of 10k gas. (i.e., 2 = 20k gas).
        uint16 gasLimit10k;
        // Storage slot 4 //
        // Fee paid for this request at creation time. Stored so refunds remain correct
        // even if the protocol fee changes later.
        uint128 feePaid;
    }
}
