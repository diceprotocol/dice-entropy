// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

import {IEntropyV2} from "./IEntropyV2.sol";
import {DiceStructsV2} from "./DiceStructsV2.sol";
import {DiceErrors} from "./DiceErrors.sol";

/// @notice Full Dice Protocol interface — combines V2 interface with provider management.
interface IEntropy is IEntropyV2 {
    /// @notice Admin-only: register a provider at a specific address.
    /// Exclusive mode — no permissionless registration.
    /// @param providerAddress The address of the provider to register
    /// @param feeInWei The per-request fee the provider charges
    /// @param commitment The provider's initial hash chain commitment (x0)
    /// @param commitmentMetadata Optional metadata for commitment management
    /// @param chainLength The number of values in the hash chain including the commitment (>= 1)
    /// @param uri Optional URI where clients can retrieve revelations
    function registerFor(
        address providerAddress,
        uint128 feeInWei,
        bytes32 commitment,
        bytes calldata commitmentMetadata,
        uint64 chainLength,
        bytes calldata uri
    ) external;

    /// @notice Legacy provider withdrawal path (disabled in the single-fee model)
    /// @param amount The amount to withdraw in wei
    function withdraw(uint128 amount) external;

    /// @notice Legacy fee-manager withdrawal path (disabled in the single-fee model)
    /// @param provider The provider address
    /// @param amount The amount to withdraw in wei
    function withdrawAsFeeManager(address provider, uint128 amount) external;

    /// @notice Reveal the provider's random number for a request (no callback)
    /// @param provider The provider address
    /// @param sequenceNumber The request's sequence number
    /// @param userRevelation The user's revealed random number
    /// @param providerRevelation The provider's revealed random number
    /// @return randomNumber The generated random number
    function reveal(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRevelation,
        bytes32 providerRevelation
    ) external returns (bytes32 randomNumber);

    /// @notice Reveal the provider's random number and trigger the requester's callback
    /// @param provider The provider address
    /// @param sequenceNumber The request's sequence number
    /// @param userRandomNumber The user's random number
    /// @param providerRevelation The provider's revealed random number
    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomNumber,
        bytes32 providerRevelation
    ) external;

    /// @notice Refund a stuck active request after the refund timeout has elapsed.
    /// @dev Only the original requester can call this. Clears the request and returns feePaid.
    /// @param provider The provider address
    /// @param sequenceNumber The request sequence number
    function refundRequest(address provider, uint64 sequenceNumber) external;

    /// @notice Get the L1-block delay required before a stuck request can be refunded
    function getRefundDelayBlocks() external view returns (uint64 delayBlocks);

    /// @notice Get provider info (V1 struct format, kept for compatibility)
    function getProviderInfo(address provider)
        external
        view
        returns (DiceStructsV2.ProviderInfo memory info);

    /// @notice Get a request by provider and sequence number (V1 struct format)
    function getRequest(address provider, uint64 sequenceNumber)
        external
        view
        returns (DiceStructsV2.Request memory req);

    /// @notice Get the fee for a request with the default gas limit
    function getFee(address provider) external view returns (uint128 feeAmount);

    /// @notice Get total accrued protocol fees
    function getAccruedTreasuryFees() external view returns (uint128 accruedFeesInWei);

    /// @notice Set the provider's per-request fee
    function setProviderFee(uint128 newFeeInWei) external;

    /// @notice Legacy fee-manager fee update path (disabled in the single-fee model)
    function setProviderFeeAsFeeManager(address provider, uint128 newFeeInWei) external;

    /// @notice Set the provider's URI
    function setProviderUri(bytes calldata newUri) external;

    /// @notice Legacy fee-manager configuration path (disabled in the single-fee model)
    function setFeeManager(address manager) external;

    /// @notice Set the maximum number of hashes to record in a request
    function setMaxNumHashes(uint32 maxNumHashes) external;

    /// @notice Set the default gas limit for callback requests
    function setDefaultGasLimit(uint32 gasLimit) external;

    /// @notice Advance the provider commitment to reduce numHashes for future requests
    function advanceProviderCommitment(
        address provider,
        uint64 advancedSequenceNumber,
        bytes32 providerRevelation
    ) external;

    /// @notice Construct a user commitment from a random number
    function constructUserCommitment(bytes32 userRandomness) external pure returns (bytes32 userCommitment);

    /// @notice Combine user and provider random values (with optional blockhash)
    function combineRandomValues(
        bytes32 userRandomness,
        bytes32 providerRandomness,
        bytes32 blockHash
    ) external pure returns (bytes32 combinedRandomness);
}
