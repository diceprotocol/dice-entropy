// SPDX-License-Identifier: Apache-2.0
// Derived from Pyth Entropy (https://github.com/pyth-network/pyth-crosschain), Apache-2.0
// Copyright 2024 Pyth Network — original architecture and interfaces
// Copyright 2026 Dice Protocol — modifications for Robinhood Chain deployment

pragma solidity ^0.8.0;

import {DiceStructsV2} from "./sdk/DiceStructsV2.sol";
import {DiceErrors} from "./sdk/DiceErrors.sol";
import {DiceEventsV2} from "./sdk/DiceEventsV2.sol";
import {DiceStatusConstants} from "./sdk/DiceStatusConstants.sol";
import {IEntropy} from "./sdk/IEntropy.sol";
import {IEntropyV2} from "./sdk/IEntropyV2.sol";
import {IEntropyConsumer} from "./sdk/IEntropyConsumer.sol";

import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {ExcessivelySafeCall} from "@excessively-safe-call/src/ExcessivelySafeCall.sol";

import {DiceState} from "./DiceState.sol";

/// @title DiceEntropy
/// @notice Trustless commit-reveal randomness oracle for Robinhood Chain.
///         Dice Protocol RNG contract. Key features:
///         - Immutable (no proxy, no upgradability)
///         - V2 API only (V1 deprecated methods removed)
///         - No governance contract (simple admin role)
///         - Single flat protocol fee, configured on-chain, with vault withdrawal by admin
///         - Exclusive provider registration (admin-only via registerFor)
///         - No blockhash in result (useBlockHash always false for V2)
/// @dev Security: unbiased as long as either the provider or the user is honest.
///      The provider cannot bias because the user's commit is hidden at request time.
///      The user cannot bias because the provider's value is locked in the hash chain.
contract DiceEntropy is IEntropy, DiceState {
    using ExcessivelySafeCall for address;

    uint32 public constant TEN_THOUSAND = 10000;
    uint32 public constant MAX_GAS_LIMIT = uint32(type(uint16).max) * TEN_THOUSAND;

    // ============================================================
    //                        CONSTRUCTOR
    // ============================================================

    /// @param admin The admin address (can set default provider, change fee, transfer ownership)
    /// @param feeInWei Fee per request in wei (all goes to vault)
    /// @param defaultProvider The initial default provider address
    /// @param prefillRequestStorage If true, pre-writes request storage slots for gas consistency
    /// @param vault The vault address that receives all protocol fees
    /// @param providerCommitment The hash chain commitment to auto-register the default provider
    /// @param providerChainLength The chain length for the default provider
    /// @param providerCommitmentMetadata Bincode-serialized CommitmentMetadata {seed, chain_length}
    /// @param refundDelayBlocks L1 blocks that must elapse before a stuck request can be refunded
    constructor(
        address admin,
        uint128 feeInWei,
        address defaultProvider,
        bool prefillRequestStorage,
        address vault,
        bytes32 providerCommitment,
        uint64 providerChainLength,
        bytes memory providerCommitmentMetadata,
        uint64 refundDelayBlocks
    ) {
        require(admin != address(0), "admin is zero address");
        require(defaultProvider != address(0), "defaultProvider is zero address");
        require(vault != address(0), "vault is zero address");
        if (providerChainLength > 0) {
            require(providerCommitment != bytes32(0), "commitment is zero");
        }

        _state.admin = admin;
        _state.feeInWei = feeInWei;
        _state.accruedFeesInWei = 0;
        _state.vault = vault;
        _state.defaultProvider = defaultProvider;
        _state.refundDelayBlocks = refundDelayBlocks;

        if (prefillRequestStorage) {
            for (uint8 i = 0; i < NUM_REQUESTS; i++) {
                DiceStructsV2.Request storage req = _state.requests[i];
                req.provider = address(1);
                req.blockNumber = 1234;
                req.commitment = hex"0123";
            }
        }

        // Auto-register default provider if commitment + chain length provided
        if (providerChainLength > 0) {
            DiceStructsV2.ProviderInfo storage provider = _state.providers[defaultProvider];
            provider.originalCommitment = providerCommitment;
            provider.originalCommitmentSequenceNumber = 0;
            provider.currentCommitment = providerCommitment;
            provider.currentCommitmentSequenceNumber = 0;
            provider.endSequenceNumber = providerChainLength;
            provider.sequenceNumber = 1;
            provider.commitmentMetadata = providerCommitmentMetadata;
            emit DiceEventsV2.Registered(defaultProvider, bytes(""));
        }
    }

    // ============================================================
    //                     PROVIDER REGISTRATION
    // ============================================================

    /// @inheritdoc IEntropy
    function registerFor(
        address providerAddress,
        uint128 feeInWei,
        bytes32 commitment,
        bytes calldata commitmentMetadata,
        uint64 chainLength,
        bytes calldata uri
    ) external override {
        if (msg.sender != _state.admin) revert DiceErrors.Unauthorized();
        if (chainLength == 0) revert DiceErrors.AssertionFailure();
        if (providerAddress == address(0)) revert DiceErrors.AssertionFailure();

        DiceStructsV2.ProviderInfo storage provider = _state.providers[providerAddress];

        // Guard: cannot re-register while requests are in-flight.
        // If the provider already exists, all outstanding requests must be
        // settled before re-registration to avoid making them unfulfillable.
        // "Settled" means the last assigned sequence number has been revealed
        // or commitment advanced to it.
        if (provider.sequenceNumber != 0) {
            require(
                provider.currentCommitmentSequenceNumber >= provider.sequenceNumber - 1,
                "in-flight requests exist"
            );
        }

        // feeInWei parameter is retained for interface compatibility but ignored in the single-fee model
        provider.feeInWei = 0; // per-provider fee is unused in the single-fee model
        provider.originalCommitment = commitment;
        provider.originalCommitmentSequenceNumber = provider.sequenceNumber;
        provider.currentCommitment = commitment;
        provider.currentCommitmentSequenceNumber = provider.sequenceNumber;
        provider.commitmentMetadata = commitmentMetadata;
        provider.endSequenceNumber = provider.sequenceNumber + chainLength;
        provider.uri = uri;
        provider.sequenceNumber += 1;

        emit DiceEventsV2.Registered(providerAddress, bytes(""));
    }

    // ============================================================
    //                       FEE MANAGEMENT
    // ============================================================

    /// @notice Withdraw accrued fees to the vault address.
    /// @dev Only callable by the admin.
    function withdrawFees(uint128 amount) external {
        require(msg.sender == _state.admin, "Only admin");
        require(_state.accruedFeesInWei >= amount, "Insufficient balance");
        _state.accruedFeesInWei -= amount;
        (bool sent,) = _state.vault.call{value: amount}("");
        require(sent, "vault withdrawal failed");
    }

    // ============================================================
    //                       REQUEST HANDLING
    // ============================================================

    /// @dev Internal helper that allocates and stores a new request.
    function requestHelper(
        address provider,
        bytes32 userCommitment,
        bool useBlockhash,
        bool isRequestWithCallback,
        uint32 callbackGasLimit
    ) internal returns (DiceStructsV2.Request storage req) {
        DiceStructsV2.ProviderInfo storage providerInfo = _state.providers[provider];
        if (_state.providers[provider].sequenceNumber == 0) revert DiceErrors.NoSuchProvider();

        // Assign a sequence number
        uint64 assignedSequenceNumber = providerInfo.sequenceNumber;
        if (assignedSequenceNumber >= providerInfo.endSequenceNumber) revert DiceErrors.OutOfRandomness();
        providerInfo.sequenceNumber += 1;

        // Single flat fee, exact payment only
        uint128 requiredFee = getFeeV2(provider, callbackGasLimit);
        if (msg.value != requiredFee) revert DiceErrors.InsufficientFee();
        _state.accruedFeesInWei += requiredFee;

        // Store the request
        req = allocRequest(provider, assignedSequenceNumber);
        req.provider = provider;
        req.sequenceNumber = assignedSequenceNumber;
        req.numHashes = SafeCast.toUint32(assignedSequenceNumber - providerInfo.currentCommitmentSequenceNumber);
        if (providerInfo.maxNumHashes != 0 && req.numHashes > providerInfo.maxNumHashes) {
            revert DiceErrors.LastRevealedTooOld();
        }
        req.commitment = keccak256(bytes.concat(userCommitment, providerInfo.currentCommitment));
        req.requester = msg.sender;
        req.blockNumber = SafeCast.toUint64(block.number);
        req.useBlockhash = useBlockhash;
        req.callbackStatus = isRequestWithCallback
            ? DiceStatusConstants.CALLBACK_NOT_STARTED
            : DiceStatusConstants.CALLBACK_NOT_NECESSARY;
        req.feePaid = requiredFee;

        if (providerInfo.defaultGasLimit == 0) {
            req.gasLimit10k = 0;
        } else {
            req.gasLimit10k = roundTo10kGas(
                callbackGasLimit < providerInfo.defaultGasLimit ? providerInfo.defaultGasLimit : callbackGasLimit
            );
        }
    }

    /// @inheritdoc IEntropyV2
    /// @dev Disabled legacy overload retained for interface compatibility. Users must supply their own entropy through the explicit requestV2(address,bytes32,uint32) path.
    function requestV2() external payable override returns (uint64 assignedSequenceNumber) {
        revert DiceErrors.AssertionFailure();
    }

    /// @inheritdoc IEntropyV2
    /// @dev Disabled legacy overload retained for interface compatibility. Users must supply their own entropy through the explicit requestV2(address,bytes32,uint32) path.
    function requestV2(uint32 gasLimit) external payable override returns (uint64 assignedSequenceNumber) {
        revert DiceErrors.AssertionFailure();
    }

    /// @inheritdoc IEntropyV2
    /// @dev Disabled legacy overload retained for interface compatibility. Users must supply their own entropy through the explicit requestV2(address,bytes32,uint32) path.
    function requestV2(address provider, uint32 gasLimit)
        external
        payable
        override
        returns (uint64 assignedSequenceNumber)
    {
        revert DiceErrors.AssertionFailure();
    }

    /// @inheritdoc IEntropyV2
    function requestV2(address provider, bytes32 userRandomNumber, uint32 gasLimit)
        public
        payable
        override
        returns (uint64)
    {
        DiceStructsV2.Request storage req = requestHelper(
            provider,
            constructUserCommitment(userRandomNumber),
            false,
            true,
            gasLimit
        );

        emit DiceEventsV2.Requested(
            provider,
            req.requester,
            req.sequenceNumber,
            userRandomNumber,
            uint32(req.gasLimit10k) * TEN_THOUSAND,
            bytes("")
        );
        return req.sequenceNumber;
    }

    // ============================================================
    //                        REVEAL
    // ============================================================

    /// @dev Internal: validates revelations and computes the random number.
    function revealHelper(
        DiceStructsV2.Request storage req,
        bytes32 userContribution,
        bytes32 providerContribution
    ) internal returns (bytes32 randomNumber, bytes32 blockHash) {
        bytes32 providerCommitment = constructProviderCommitment(req.numHashes, providerContribution);
        bytes32 userCommitment = constructUserCommitment(userContribution);
        if (keccak256(bytes.concat(userCommitment, providerCommitment)) != req.commitment) {
            revert DiceErrors.IncorrectRevelation();
        }

        blockHash = bytes32(uint256(0));
        if (req.useBlockhash) {
            bytes32 _blockHash = blockhash(req.blockNumber);
            if (_blockHash == bytes32(uint256(0))) revert DiceErrors.BlockhashUnavailable();
            blockHash = _blockHash;
        }

        randomNumber = combineRandomValues(userContribution, providerContribution, blockHash);

        // Advance the provider's current commitment
        DiceStructsV2.ProviderInfo storage providerInfo = _state.providers[req.provider];
        if (providerInfo.currentCommitmentSequenceNumber < req.sequenceNumber) {
            providerInfo.currentCommitmentSequenceNumber = req.sequenceNumber;
            providerInfo.currentCommitment = providerContribution;
        }
    }

    /// @inheritdoc IEntropy
    function reveal(
        address provider,
        uint64 sequenceNumber,
        bytes32 userContribution,
        bytes32 providerContribution
    ) public override returns (bytes32 randomNumber) {
        DiceStructsV2.Request storage req = findActiveRequest(provider, sequenceNumber);
        if (req.callbackStatus != DiceStatusConstants.CALLBACK_NOT_NECESSARY) revert DiceErrors.InvalidRevealCall();
        if (req.requester != msg.sender) revert DiceErrors.Unauthorized();

        bytes32 blockHash;
        (randomNumber, blockHash) = revealHelper(req, userContribution, providerContribution);

        emit DiceEventsV2.Revealed(
            provider, req.requester, sequenceNumber, randomNumber, userContribution, providerContribution, false, "", 0, bytes("")
        );
        clearRequest(provider, sequenceNumber);
    }

    /// @inheritdoc IEntropy
    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 userContribution,
        bytes32 providerContribution
    ) public override {
        DiceStructsV2.Request storage req = findActiveRequest(provider, sequenceNumber);
        if (
            !(req.callbackStatus == DiceStatusConstants.CALLBACK_NOT_STARTED
                || req.callbackStatus == DiceStatusConstants.CALLBACK_FAILED)
        ) revert DiceErrors.InvalidRevealCall();

        bytes32 randomNumber;
        (randomNumber,) = revealHelper(req, userContribution, providerContribution);

        if (req.gasLimit10k != 0 && req.callbackStatus == DiceStatusConstants.CALLBACK_NOT_STARTED) {
            req.callbackStatus = DiceStatusConstants.CALLBACK_IN_PROGRESS;

            bool success;
            bytes memory ret;
            uint256 startingGas = gasleft();

            (success, ret) = req.requester.excessivelySafeCall(
                uint256(req.gasLimit10k) * TEN_THOUSAND,
                0,
                256,
                abi.encodeWithSelector(
                    IEntropyConsumer._entropyCallback.selector, sequenceNumber, provider, randomNumber
                )
            );

            uint32 gasUsed = SafeCast.toUint32(startingGas - gasleft());
            req.callbackStatus = DiceStatusConstants.CALLBACK_NOT_STARTED;

            if (success) {
                emit DiceEventsV2.Revealed(
                    provider, req.requester, sequenceNumber, randomNumber, userContribution, providerContribution, false, ret, gasUsed, bytes("")
                );
                clearRequest(provider, sequenceNumber);
            } else if ((startingGas * 31) / 32 > uint256(req.gasLimit10k) * TEN_THOUSAND) {
                emit DiceEventsV2.Revealed(
                    provider, req.requester, sequenceNumber, randomNumber, userContribution, providerContribution, true, ret, gasUsed, bytes("")
                );
                req.callbackStatus = DiceStatusConstants.CALLBACK_FAILED;
            } else {
                revert DiceErrors.InsufficientGas();
            }
        } else {
            address callAddress = req.requester;
            clearRequest(provider, sequenceNumber);

            uint len;
            assembly { len := extcodesize(callAddress) }
            bool callbackFailed = false;
            uint256 startingGas = gasleft();
            if (len != 0) {
                // Use excessivelySafeCall for the no-gas-limit / retry path too.
                // This prevents a reverting consumer callback from reverting the
                // entire reveal transaction, which would leave the request stuck.
                (bool callbackSuccess,) = callAddress.excessivelySafeCall(
                    gasleft() * 15 / 16,
                    0,
                    256,
                    abi.encodeWithSelector(
                        IEntropyConsumer._entropyCallback.selector, sequenceNumber, provider, randomNumber
                    )
                );
                callbackFailed = !callbackSuccess;
            }
            uint32 gasUsed = SafeCast.toUint32(startingGas - gasleft());

            emit DiceEventsV2.Revealed(
                provider, callAddress, sequenceNumber, randomNumber, userContribution, providerContribution, callbackFailed, "", gasUsed, bytes("")
            );
        }
    }

    // ============================================================
    //                         REFUNDS
    // ============================================================

    /// @inheritdoc IEntropy
    function refundRequest(address provider, uint64 sequenceNumber) external override {
        DiceStructsV2.Request storage req = findActiveRequest(provider, sequenceNumber);
        if (req.requester != msg.sender) revert DiceErrors.Unauthorized();
        // On Robinhood/Arbitrum Nitro, block.number is L1 (~12s/block). Default 6 ≈ ~72s.
        if (block.number < uint256(req.blockNumber) + uint256(_state.refundDelayBlocks)) {
            revert DiceErrors.RefundNotAvailable();
        }

        address requester = req.requester;
        uint128 amount = req.feePaid;

        // Clear first to prevent reentrancy / double-refund.
        clearRequest(provider, sequenceNumber);

        if (amount > 0) {
            require(_state.accruedFeesInWei >= amount, "Insufficient accrued fees");
            _state.accruedFeesInWei -= amount;
            (bool sent,) = requester.call{value: amount}("");
            require(sent, "refund transfer failed");
        }

        emit DiceEventsV2.RequestRefunded(provider, requester, sequenceNumber, amount, bytes(""));
    }

    /// @inheritdoc IEntropy
    function getRefundDelayBlocks() external view override returns (uint64 delayBlocks) {
        delayBlocks = _state.refundDelayBlocks;
    }

    // ============================================================
    //                  COMMITMENT ADVANCEMENT
    // ============================================================

    /// @inheritdoc IEntropy
    function advanceProviderCommitment(
        address provider,
        uint64 advancedSequenceNumber,
        bytes32 providerRevelation
    ) public override {
        DiceStructsV2.ProviderInfo storage providerInfo = _state.providers[provider];
        if (advancedSequenceNumber <= providerInfo.currentCommitmentSequenceNumber) revert DiceErrors.UpdateTooOld();
        if (advancedSequenceNumber >= providerInfo.endSequenceNumber) revert DiceErrors.AssertionFailure();

        uint32 numHashes = SafeCast.toUint32(advancedSequenceNumber - providerInfo.currentCommitmentSequenceNumber);
        bytes32 providerCommitment = constructProviderCommitment(numHashes, providerRevelation);
        if (providerCommitment != providerInfo.currentCommitment) revert DiceErrors.IncorrectRevelation();

        providerInfo.currentCommitmentSequenceNumber = advancedSequenceNumber;
        providerInfo.currentCommitment = providerRevelation;

        // If the advancement passes the sequence number, bump it to prevent
        // assigning sequence numbers that are already revealed.
        if (providerInfo.currentCommitmentSequenceNumber >= providerInfo.sequenceNumber) {
            providerInfo.sequenceNumber = providerInfo.currentCommitmentSequenceNumber + 1;
        }
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @inheritdoc IEntropy
    function getProviderInfo(address provider) public view override returns (DiceStructsV2.ProviderInfo memory info) {
        info = _state.providers[provider];
    }

    /// @inheritdoc IEntropyV2
    function getProviderInfoV2(address provider) public view override returns (DiceStructsV2.ProviderInfo memory info) {
        info = _state.providers[provider];
    }

    /// @inheritdoc IEntropyV2
    function getDefaultProvider() public view override returns (address provider) {
        provider = _state.defaultProvider;
    }

    /// @inheritdoc IEntropy
    function getRequest(address provider, uint64 sequenceNumber)
        public
        view
        override
        returns (DiceStructsV2.Request memory req)
    {
        req = findRequest(provider, sequenceNumber);
    }

    /// @inheritdoc IEntropyV2
    function getRequestV2(address provider, uint64 sequenceNumber)
        public
        view
        override
        returns (DiceStructsV2.Request memory req)
    {
        req = findRequest(provider, sequenceNumber);
    }

    /// @inheritdoc IEntropy
    function getFee(address provider) public view override returns (uint128 feeAmount) {
        return _state.feeInWei;
    }

    /// @inheritdoc IEntropyV2
    function getFeeV2() external view override returns (uint128 feeAmount) {
        return _state.feeInWei;
    }

    /// @inheritdoc IEntropyV2
    function getFeeV2(uint32 gasLimit) external view override returns (uint128 feeAmount) {
        return _state.feeInWei;
    }

    /// @inheritdoc IEntropyV2
    function getFeeV2(address provider, uint32 gasLimit) public view override returns (uint128 feeAmount) {
        return _state.feeInWei;
    }

    /// @notice Get total fees accrued in the contract.
    function getAccruedFees() public view returns (uint128) {
        return _state.accruedFeesInWei;
    }

    /// @notice Get the current fee per request.
    function getProtocolFee() public view returns (uint128) {
        return _state.feeInWei;
    }

    // ============================================================
    //                   PROVIDER CONFIGURATION
    // ============================================================

    /// @inheritdoc IEntropy
    function setProviderFee(uint128 newFeeInWei) external override {
        // Disabled in the single-fee model; admin manages protocol fee via setFee()
        revert DiceErrors.Unauthorized();
    }

    /// @inheritdoc IEntropy
    function setProviderFeeAsFeeManager(address provider, uint128 newFeeInWei) external override {
        revert DiceErrors.Unauthorized();
    }

    /// @inheritdoc IEntropy
    function setProviderUri(bytes calldata newUri) external override {
        DiceStructsV2.ProviderInfo storage provider = _state.providers[msg.sender];
        if (provider.sequenceNumber == 0) revert DiceErrors.NoSuchProvider();
        bytes memory oldUri = provider.uri;
        provider.uri = newUri;
        emit DiceEventsV2.ProviderUriUpdated(msg.sender, oldUri, newUri, bytes(""));
    }

    /// @inheritdoc IEntropy
    function setFeeManager(address manager) external override {
        // Fee manager model removed — single fee to vault
        revert DiceErrors.Unauthorized();
    }

    /// @inheritdoc IEntropy
    function setMaxNumHashes(uint32 maxNumHashes) external override {
        DiceStructsV2.ProviderInfo storage provider = _state.providers[msg.sender];
        if (provider.sequenceNumber == 0) revert DiceErrors.NoSuchProvider();
        uint32 oldMaxNumHashes = provider.maxNumHashes;
        provider.maxNumHashes = maxNumHashes;
        emit DiceEventsV2.ProviderMaxNumHashesAdvanced(msg.sender, oldMaxNumHashes, maxNumHashes, bytes(""));
    }

    /// @inheritdoc IEntropy
    function setDefaultGasLimit(uint32 gasLimit) external override {
        DiceStructsV2.ProviderInfo storage provider = _state.providers[msg.sender];
        if (provider.sequenceNumber == 0) revert DiceErrors.NoSuchProvider();
        roundTo10kGas(gasLimit);
        uint32 oldGasLimit = provider.defaultGasLimit;
        provider.defaultGasLimit = gasLimit;
        emit DiceEventsV2.ProviderDefaultGasLimitUpdated(msg.sender, oldGasLimit, gasLimit, bytes(""));
    }

    /// @inheritdoc IEntropy
    function withdraw(uint128 amount) public override {
        // Per-provider withdrawal removed — admin uses withdrawFees() to send to vault
        revert DiceErrors.Unauthorized();
    }

    /// @inheritdoc IEntropy
    function withdrawAsFeeManager(address provider, uint128 amount) external override {
        revert DiceErrors.Unauthorized();
    }

    /// @notice Get accrued protocol fees via the legacy backward-compatible interface method.
    function getAccruedTreasuryFees() public view override returns (uint128) {
        return _state.accruedFeesInWei;
    }

    // ============================================================
    //                    ADMIN FUNCTIONS
    // ============================================================

    /// @notice Propose a new admin. Must be accepted by the new admin.
    function proposeAdmin(address newAdmin) external {
        require(msg.sender == _state.admin, "Only admin");
        require(newAdmin != address(0), "admin is zero address");
        _state.proposedAdmin = newAdmin;
    }

    /// @notice Accept the admin role. Must be called by the proposed admin.
    function acceptAdmin() external {
        require(msg.sender == _state.proposedAdmin, "Not proposed");
        _state.admin = _state.proposedAdmin;
        _state.proposedAdmin = address(0);
    }

    /// @notice Set the default provider. Only admin.
    function setDefaultProvider(address provider) external {
        require(msg.sender == _state.admin, "Only admin");
        _state.defaultProvider = provider;
    }

    /// @notice Set the protocol fee per request. Only admin.
    function setFee(uint128 feeInWei) external {
        require(msg.sender == _state.admin, "Only admin");
        _state.feeInWei = feeInWei;
    }

    // ============================================================
    //                    PURE FUNCTIONS
    // ============================================================

    /// @inheritdoc IEntropy
    function constructUserCommitment(bytes32 userRandomness) public pure override returns (bytes32 userCommitment) {
        userCommitment = keccak256(bytes.concat(userRandomness));
    }

    /// @inheritdoc IEntropy
    function combineRandomValues(
        bytes32 userRandomness,
        bytes32 providerRandomness,
        bytes32 blockHash
    ) public pure override returns (bytes32 combinedRandomness) {
        combinedRandomness = keccak256(abi.encodePacked(userRandomness, providerRandomness, blockHash));
    }

    // ============================================================
    //                   INTERNAL HELPERS
    // ============================================================

    function roundTo10kGas(uint32 gas) internal pure returns (uint16) {
        if (gas > MAX_GAS_LIMIT) revert DiceErrors.MaxGasLimitExceeded();
        uint32 gas10k = gas / TEN_THOUSAND;
        if (gas10k * TEN_THOUSAND < gas) gas10k += 1;
        return SafeCast.toUint16(gas10k);
    }

    function requestKey(address provider, uint64 sequenceNumber)
        internal
        pure
        returns (bytes32 hash, uint8 shortHash)
    {
        hash = keccak256(abi.encodePacked(provider, sequenceNumber));
        shortHash = uint8(hash[0] & NUM_REQUESTS_MASK);
    }

    function constructProviderCommitment(uint64 numHashes, bytes32 revelation)
        internal
        pure
        returns (bytes32 currentHash)
    {
        currentHash = revelation;
        while (numHashes > 0) {
            currentHash = keccak256(bytes.concat(currentHash));
            numHashes -= 1;
        }
    }

    function findActiveRequest(address provider, uint64 sequenceNumber)
        internal
        view
        returns (DiceStructsV2.Request storage req)
    {
        req = findRequest(provider, sequenceNumber);
        if (!isActive(req) || req.provider != provider || req.sequenceNumber != sequenceNumber) {
            revert DiceErrors.NoSuchRequest();
        }
    }

    function findRequest(address provider, uint64 sequenceNumber)
        internal
        view
        returns (DiceStructsV2.Request storage req)
    {
        (bytes32 key, uint8 shortKey) = requestKey(provider, sequenceNumber);
        req = _state.requests[shortKey];
        if (req.provider == provider && req.sequenceNumber == sequenceNumber) {
            return req;
        } else {
            req = _state.requestsOverflow[key];
        }
    }

    function clearRequest(address provider, uint64 sequenceNumber) internal {
        (bytes32 key, uint8 shortKey) = requestKey(provider, sequenceNumber);
        DiceStructsV2.Request storage req = _state.requests[shortKey];
        if (req.provider == provider && req.sequenceNumber == sequenceNumber) {
            req.sequenceNumber = 0;
        } else {
            delete _state.requestsOverflow[key];
        }
    }

    function allocRequest(address provider, uint64 sequenceNumber)
        internal
        returns (DiceStructsV2.Request storage req)
    {
        (, uint8 shortKey) = requestKey(provider, sequenceNumber);
        req = _state.requests[shortKey];
        if (isActive(req)) {
            (bytes32 reqKey,) = requestKey(req.provider, req.sequenceNumber);
            _state.requestsOverflow[reqKey] = req;
        }
    }

    function isActive(DiceStructsV2.Request storage req) internal view returns (bool) {
        return req.sequenceNumber != 0;
    }
}
