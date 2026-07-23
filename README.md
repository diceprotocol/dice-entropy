# Dice Protocol

> Trustless commit-reveal randomness oracle for Robinhood Chain. Verifiable, unbiased on-chain RNG for gaming, NFTs, prediction markets, and DeFi.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Chain](https://img.shields.io/badge/Chain-Robinhood%20Chain%204663-orange)](https://robinhoodchain.blockscout.com)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636)](https://foundry.paradigm.xyz/)
[![Audit](https://img.shields.io/badge/Audit-Clean%20(0%20critical)-green)](docs/security-audit.md)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Quickstart](#quickstart)
  - [1. Deploy a Consumer Contract](#1-deploy-a-consumer-contract)
  - [2. Request Randomness](#2-request-randomness)
  - [3. TypeScript SDK Usage](#3-typescript-sdk-usage)
- [Contract Addresses](#contract-addresses)
- [Network Configuration](#network-configuration)
- [API Reference](#api-reference)
  - [Smart Contract API](#smart-contract-api)
  - [SDK API](#sdk-api)
- [Tyche Keeper](#tyche-keeper)
- [Security](#security)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Dice Protocol is a commit-reveal randomness oracle deployed on Robinhood Chain (chain ID 4663), an Arbitrum Nitro-based Layer 2. It delivers cryptographically secure, unbiased on-chain random numbers to any smart contract via a hash-chain commitment scheme.

The protocol combines user-contributed randomness with provider-revealed values using Keccak256, producing manipulation-resistant results that are verifiable on-chain. Neither the provider nor the requester can bias the outcome — the result is random as long as either party is honest.

Dice Protocol is the live RNG oracle on Robinhood Chain, operating under an exclusive provider model with a flat per-request fee of 0.000025 ETH. The on-chain contract is immutable (no proxy, no upgrade path), and the Tyche keeper — a Rust auto-reveal service — handles automated reveal submission 24/7.

---

## Features

- **Commit-reveal RNG** — Hash-chain commitment scheme with Keccak256. Provider pre-commits to a hash chain (live v10 currently registered with 500,000 values; longer chains supported); each request reveals the next.
- **Unbiased** — Neither provider nor user can influence the outcome. Random as long as either party is honest.
- **Verifiable on-chain** — Every reveal is independently checkable via `keccak256(reveal) == previousCommitment`.
- **Low latency** — ~2–5 seconds per request (1 block confirmation on Robinhood Chain).
- **Flat fee model** — 0.000025 ETH per request. No hidden costs, no gas subsidies, no protocol fee splits.
- **Immutable contract** — No proxy, no governance, no upgrade mechanism. Logic is permanent once deployed.
- **Auto-reveal** — The Tyche keeper service monitors for `Requested` events and submits reveals automatically.
- **Callback delivery** — Random numbers are delivered directly to consumer contracts via `entropyCallback()` in the same reveal transaction.
- **TypeScript SDK** — Full-featured SDK for off-chain integration, event listening, and utility functions.
- **Security audited** — Clean audit with zero critical or high-severity findings. See [docs/security-audit.md](docs/security-audit.md).

---

## How It Works

```
Consumer Contract            DiceEntropy (on-chain)           Tyche Keeper (off-chain)
     │                              │                                │
     │── requestV2(provider,        │                                │
     │    userRandom, gasLimit) ──→ │                                │
     │   {value: 0.000025 ETH}     │                                │
     │                              │── emit Requested(...) ───────→ │
     │                              │                                │
     │                              │                  Tyche detects │
     │                              │                  event, computes
     │                              │                  next hash-chain
     │                              │                  reveal value   │
     │                              │                                │
     │                              │←── revealWithCallback(         │
     │                              │      seq, userRandom,          │
     │                              │      providerReveal) ──────────│
     │                              │                                │
     │   Contract verifies:         │                                │
     │   keccak256(providerReveal)  │                                │
     │     == currentCommitment     │                                │
     │                              │                                │
     │   randomNumber =             │                                │
     │     keccak256(userRandom,    │                                │
     │               providerReveal)│                                │
     │                              │                                │
     │←── entropyCallback(          │                                │
     │      seq, provider,          │                                │
     │      randomNumber) ──────────│                                │
     │                              │                                │
```

**Security guarantee:** The provider cannot predict the user's random value at commitment time. The user cannot bias the provider's value — it's locked in the hash chain. The result is unpredictable to both parties.

---

## Architecture

```
dice-protocol/
├── contracts/               # Solidity smart contracts (Foundry)
│   ├── src/
│   │   ├── DiceEntropy.sol           # Core RNG contract (commit-reveal + hash chain)
│   │   ├── DiceState.sol             # Storage layout
│   │   ├── TestConsumer.sol          # Reference consumer implementation
│   │   └── sdk/                      # Interfaces & libraries
│   │       ├── IEntropy.sol          # Core entropy interface
│   │       ├── IEntropyV2.sol        # V2 request/reveal interface
│   │       ├── IEntropyConsumer.sol  # Consumer base contract
│   │       ├── DiceStructsV2.sol     # Struct definitions
│   │       ├── DiceErrors.sol        # Custom error definitions
│   │       ├── DiceEventsV2.sol      # Event definitions
│   │       ├── DiceStatusConstants.sol
│   │       └── PRNG.sol              # PRNG utility
│   ├── script/
│   │   └── DeployDiceV6.s.sol        # Deployment script
│   ├── test/                         # Foundry test suite
│   └── foundry.toml
│
├── tyche/                   # Rust auto-reveal keeper service
│   ├── src/
│   │   ├── api/                      # REST API (port 34000)
│   │   ├── chain/                    # Blockchain reader/adapter
│   │   ├── keeper/                   # Reveal loop & tx submission
│   │   └── command/                  # CLI verbs (run, setup-provider)
│   ├── config/                       # Configuration files
│   ├── migrations/                   # SQLite schema migrations
│   └── Dockerfile
│
├── sdk/                     # TypeScript SDK
│   ├── src/
│   │   ├── index.ts                  # DiceProtocol class + exports
│   │   ├── abi.json                  # Contract ABI
│   │   └── test.ts                   # SDK tests
│   ├── dist/                         # Compiled output
│   └── package.json
│
├── docs/                    # Full documentation
│   ├── whitepaper.md                 # Protocol specification
│   ├── ARCHITECTURE.md               # System design deep-dive
│   ├── INTEGRATION.md                # Developer integration guide
│   ├── DEPLOYMENT.md                 # Deployment pipeline
│   ├── developer-docs.md             # API reference & quickstart
│   ├── mainnet-deployment.md         # Mainnet deployment record
│   ├── testnet-deployment.md         # Testnet deployment record
│   ├── security-audit.md             # Audit report
│   ├── project-status.md             # Current project status
│   └── ROADMAP.md                    # Development roadmap
│
├── data/                    # Tyche SQLite state (gitignored)
├── keeper/                  # Keeper wallet management scripts
├── monitor/                 # Uptime & health dashboards
└── README.md
```

### System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Robinhood Chain L2 (4663)                  │
│                                                               │
│  ┌──────────────────┐    requestV2()    ┌─────────────────┐  │
│  │  Consumer dApp   │──────────────────→│                 │  │
│  │  (Game / NFT /   │←─────────────────│  DiceEntropy    │  │
│  │   Lottery / ...) │  entropyCallback  │  Contract       │  │
│  └──────────────────┘                   │                 │  │
│                                         │  · Hash chain   │  │
│                                         │    verification │  │
│                                         │  · Fee accounting│ │
│                                         │  · Callback     │  │
│                                         │    dispatch     │  │
│                                         └────────┬────────┘  │
│                                                  │            │
└──────────────────────────────────────────────────┼────────────┘
                                                   │
                                    Requested events│
                                    revealWithCallback txs
                                                   │
┌──────────────────────────────────────────────────┼────────────┐
│                 Off-chain keeper                 │            │
│                                                   ▼            │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Tyche Keeper (Rust)                       │      │
│  │                                                        │      │
│  │  · Monitors Requested events via JSON-RPC polling     │      │
│  │  · Computes reveal values from precomputed hash chain │      │
│  │  · Submits revealWithCallback transactions             │      │
│  │  · State persisted in SQLite                           │      │
│  │  · REST API on :34000 for monitoring                   │      │
│  └──────────────────────────────────────────────────────┘      │
└────────────────────────────────────────────────────────────────┘
```

---

## Quickstart

### Prerequisites

- [Foundry](https://foundry.paradigm.xyz/) (`forge`, `cast`) — for Solidity development
- [Node.js](https://nodejs.org/) 18+ — for the TypeScript SDK
- [Rust](https://rustup.rs/) — for the Tyche keeper (operators only)
- ETH on Robinhood Chain for gas + request fees

### 1. Deploy a Consumer Contract

Consumer contracts inherit `IEntropyConsumer` and implement `entropyCallback()`:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IEntropyConsumer } from "@diceprotocol/sdk/IEntropyConsumer.sol";
import { IEntropy } from "@diceprotocol/sdk/IEntropy.sol";

contract MyGame is IEntropyConsumer {
    IEntropy public immutable dice;
    address public immutable provider;
    mapping(uint64 => address) public pendingPlayers;

    // DiceEntropy mainnet address
    constructor(address _dice, address _provider) {
        dice = IEntropy(_dice);
        provider = _provider;
    }

    /// @notice Request a dice roll. Caller pays the protocol fee.
    function rollDice() external payable {
        // Generate user's random contribution
        bytes32 userRandom = keccak256(abi.encodePacked(msg.sender, block.timestamp, block.prevrandao));
        // Request randomness — fee is 0.000025 ETH
        uint64 seq = dice.requestV2{value: msg.value}(provider, userRandom, 200_000);
        pendingPlayers[seq] = msg.sender;
    }

    /// @notice Called by DiceEntropy with the verified random number
    function entropyCallback(
        uint64 sequence,
        address,
        bytes32 randomNumber
    ) internal override {
        address player = pendingPlayers[sequence];
        uint256 result = uint256(randomNumber) % 6 + 1; // 1–6
        // ... game logic here
        delete pendingPlayers[sequence];
    }

    function getEntropy() internal view override returns (address) {
        return address(dice);
    }
}
```

Deploy with Forge:

```bash
# Deploy to Robinhood Chain mainnet
forge create MyGame \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $DEPLOYER_KEY \
  --constructor-args 0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c 0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6
```

### 2. Request Randomness

From a script or dApp frontend, call `rollDice()` with the fee:

```bash
# Using cast
cast send $CONTRACT_ADDRESS "rollDice()" \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $USER_KEY \
  --value 0.000025ether
```

The Tyche keeper detects the `Requested` event within ~20 blocks, computes the reveal, and submits `revealWithCallback()`. Your contract's `entropyCallback()` fires with the random number — typically within 2–5 seconds.

### 3. TypeScript SDK Usage

Install the SDK:

```bash
npm install @diceprotocol/sdk
# or
yarn add @diceprotocol/sdk
```

Request randomness and listen for reveals:

```typescript
import { DiceProtocol, ethers } from '@diceprotocol/sdk';

// Initialize
const dice = new DiceProtocol({
  rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
  contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
});

// Load your wallet (never hardcode keys in production)
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!);

// Get the default provider address
const provider = await dice.getDefaultProvider();
console.log('Provider:', provider);

// Check the fee
const fee = await dice.getFee(provider);
console.log('Fee:', ethers.formatEther(fee), 'ETH');

// Generate a random user contribution
const userRandom = DiceProtocol.generateUserRandom();
console.log('User random:', userRandom);

// Request randomness
const seq = await dice.requestRandom(wallet, provider, userRandom);
console.log('Request sequence:', seq);

// Listen for the reveal (random number delivered)
dice.onReveal((event) => {
  if (event.sequenceNumber === seq) {
    console.log('Random number:', event.randomNumber);
    console.log('Callback failed:', event.callbackFailed);
    dice.removeAllListeners();
  }
});

// You can also query request status at any time
const request = await dice.getRequest(provider, seq);
console.log('Request status:', request);
```

---

## Contract Addresses

### Mainnet (Robinhood Chain — Chain ID 4663)

| Component      | Address                                                          |
|----------------|------------------------------------------------------------------|
| DiceEntropy    | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`                    |
| Keeper (Tyche) | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6`                    |
| Admin          | `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD`                    |
| Vault          | `0x918EAF0b2589710B0D85ef48C12a343E68263841`                    |

### Testnet (Robinhood Chain Testnet — Chain ID 46630)

| Component   | Address                                                          |
|-------------|------------------------------------------------------------------|
| DiceEntropy | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`                    |

> **Note:** The testnet uses a free tier (0 ETH fee) and a shorter hash chain (1,000 values). See [docs/testnet-deployment.md](docs/testnet-deployment.md).

---

## Network Configuration

| Parameter          | Value                                              |
|--------------------|----------------------------------------------------|
| Chain ID           | 4663                                               |
| Chain Name         | Robinhood Chain                                    |
| RPC URL            | `https://rpc.mainnet.chain.robinhood.com`          |
| Block Explorer     | [https://robinhoodchain.blockscout.com](https://robinhoodchain.blockscout.com) |
| L2 Type            | Arbitrum Nitro                                     |
| Request Fee        | 0.000025 ETH (25,000,000,000,000 wei)             |
| Hash Chain Length | **500,000** values registered on live v10 (end sequence 500003); longer chains can be registered later via registerFor                                      |
| Hash Algorithm     | Keccak256                                          |
| Example callback gas | 200,000                                            |
| Max Gas Limit      | 655,350,000 (`uint16.max × 10,000`)               |

---

## API Reference

### Smart Contract API

The DiceEntropy contract exposes a V2 API. All randomness requests go through `requestV2()` and reveals through `revealWithCallback()`.

#### Core Functions

| Function | Description |
|----------|-------------|
| `requestV2()` | Request randomness from the default provider with auto-generated user random and default gas limit. Payable. |
| `requestV2(uint32 gasLimit)` | Request with a specified callback gas limit. |
| `requestV2(address provider, uint32 gasLimit)` | Request from a specific provider. |
| `requestV2(address provider, bytes32 userRandomNumber, uint32 gasLimit)` | Full control — provider, user random, and gas limit. **Recommended.** |
| `revealWithCallback(address provider, uint64 seq, bytes32 userContribution, bytes32 providerContribution)` | Called by the keeper to reveal the provider's value and trigger the consumer's callback. |
| `reveal(address provider, uint64 seq, bytes32 userContribution, bytes32 providerContribution)` | Reveal without callback (requester calls manually). |

#### Admin Functions

| Function | Description |
|----------|-------------|
| `registerFor(address provider, uint128 fee, bytes32 commitment, bytes metadata, uint64 chainLength, bytes uri)` | Register a new provider or refresh a hash chain. Admin only. |
| `withdrawFees(uint128 amount)` | Withdraw accrued fees to the vault address. Admin only. |
| `advanceProviderCommitment(address provider, uint64 seq, bytes32 revelation)` | Advance the commitment pointer (skip leaked sequences). |

#### View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getDefaultProvider()` | `address` | The default provider address |
| `getFee(address provider)` | `uint128` | Fee in wei for a request |
| `getFeeV2(address provider, uint32 gasLimit)` | `uint128` | Fee for a specific gas limit |
| `getProviderInfoV2(address provider)` | `ProviderInfo` | Full provider state (commitment, chain, fees, etc.) |
| `getRequestV2(address provider, uint64 seq)` | `Request` | Request details by sequence number |

#### Events

| Event | Description |
|-------|-------------|
| `Requested(provider, caller, sequenceNumber, userContribution, gasLimit, ...)` | Emitted when a randomness request is made |
| `Revealed(provider, caller, sequenceNumber, randomNumber, userContribution, providerContribution, callbackFailed, ...)` | Emitted when a reveal completes |
| `Registered(provider, ...)` | Emitted when a provider is registered or refreshed |

#### Consumer Interface

Consumer contracts must inherit `IEntropyConsumer` and implement:

```solidity
function entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) internal;
function getEntropy() internal view returns (address);
```

The `_entropyCallback()` external function is called by DiceEntropy — it enforces `msg.sender == getEntropy()` so only the DiceEntropy contract can trigger the callback.

---

### SDK API

The `@diceprotocol/sdk` package provides a `DiceProtocol` class for off-chain interaction.

#### Constructor

```typescript
const dice = new DiceProtocol({
  rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
  contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
});
```

#### Read Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getDefaultProvider()` | `Promise<string>` | Default provider address |
| `getFee(provider?, gasLimit?)` | `Promise<bigint>` | Request fee in wei |
| `getProviderInfo(provider)` | `Promise<ProviderInfo>` | Full provider state |
| `getRequest(provider, seq)` | `Promise<RequestInfo>` | Request details by sequence number |
| `getAccruedTreasuryFees()` | `Promise<bigint>` | Total accrued fees |
| `getProtocolFee()` | `Promise<bigint>` | Current protocol fee per request |

#### Write Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `requestRandom(signer, provider?, userRandom, gasLimit?)` | `Promise<bigint>` | Submit a randomness request, returns sequence number |
| `revealWithCallback(signer, seq, userRandom, reveal)` | `Promise<string>` | Reveal (provider/keeper only) |
| `registerProvider(signer, fee, commitment, chainLen, uri?)` | `Promise<string>` | Register as a provider |
| `withdrawFees(signer, amount)` | `Promise<string>` | Withdraw accrued provider fees |

#### Event Listeners

| Method | Description |
|--------|-------------|
| `onRequest(callback)` | Listen for `Requested` events |
| `onReveal(callback)` | Listen for `Revealed` events (random numbers delivered) |
| `removeAllListeners()` | Stop all event listeners |

#### Utility Functions (static)

| Method | Returns | Description |
|--------|---------|-------------|
| `DiceProtocol.generateUserRandom()` | `string` | Generate a 32-byte random hex value |
| `DiceProtocol.computeUserCommitment(random)` | `string` | Hash a user random into a commitment |
| `DiceProtocol.constructProviderCommitment(numHashes, revelation)` | `string` | Construct a commitment from a revelation |
| `DiceProtocol.generateHashChain(seed, length)` | `{ commitment, revelations[] }` | Generate a full hash chain from a seed |
| `DiceProtocol.combineRandom(user, provider, blockHash?)` | `string` | Combine random values (matches on-chain computation) |

---

## Tyche Keeper

Tyche is the Rust-based auto-reveal service that powers Dice Protocol. It runs as a systemd service and handles the full reveal lifecycle:

1. **Initialization** — Reads provider info from the DiceEntropy contract, deserializes commitment metadata, reconstructs the hash chain in memory.
2. **Block watching** — Polls for new blocks, filtering for `Requested` events.
3. **Reveal computation** — Indexes into the precomputed hash chain at the correct sequence number.
4. **Transaction submission** — Sends `revealWithCallback` transactions from the keeper wallet.
5. **State persistence** — Records all processed requests in SQLite for crash recovery.

### Running Tyche

```bash
# Build
cd tyche/
cargo build --release

# Register the provider (first-time setup)
cargo run -- setup-provider --config config/dice-config.yaml

# Start the keeper
RUST_LOG=INFO cargo run -- run --config config/dice-config.yaml
```

### REST API

Tyche exposes a monitoring API on port 34000:

```
GET /v1/chains/{chain_id}/revelations/{sequence}   # Get reveal value for a sequence
GET /v1/chains/{chain_id}/requests                 # List pending requests
```

### Wallet Separation

Dice Protocol enforces a three-wallet security model:

| Role    | Type | Purpose                                      |
|---------|------|----------------------------------------------|
| Admin   | Cold | Contract admin — fee changes, withdrawals, provider management |
| Vault   | Cold | Fee recipient — receive-only                 |
| Keeper  | Hot  | Submits reveal transactions, funded with gas ETH only |

The keeper wallet cannot withdraw fees or modify contract parameters. If compromised, the attacker can only reveal randomness early or fail to reveal — they cannot steal funds.

---

## Security

### Audit Results

The DiceEntropy contract has been audited with Slither 0.11.5 and a manual review. **Zero critical or high-severity vulnerabilities.**

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0     | —      |
| High     | 0     | —      |
| Medium   | 0     | —      |
| Low      | 2     | Mitigated (gas griefing via `defaultGasLimit`; `block.timestamp` PRNG acceptable) |
| Info     | 3     | Acknowledged |

Full report: [docs/security-audit.md](docs/security-audit.md)

### Security Properties

| Property              | Guarantee                                                        |
|-----------------------|------------------------------------------------------------------|
| Unpredictability      | Provider cannot predict user's random value at commitment time   |
| Non-biasability       | User cannot influence provider's contribution                    |
| Verifiability         | Each reveal is verifiable on-chain via Keccak256                 |
| Tamper resistance     | Immutable contract — no proxy, no upgrade path                   |
| Gas bounded           | Consumers pass an explicit callback gas limit (example: 200,000)               |
| Reentrancy protection | `ExcessivelySafeCall` pattern for all untrusted callbacks        |
| Chain exhaustion      | `OutOfRandomness` revert when hash chain depleted                |

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/whitepaper.md](docs/whitepaper.md) | Full protocol specification — cryptographic design, economic model, security analysis |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and component design |
| [docs/INTEGRATION.md](docs/INTEGRATION.md) | Developer integration guide with patterns (coin flip, NFT mint, batch) |
| [docs/developer-docs.md](docs/developer-docs.md) | Quickstart, API reference, and Solidity integration paths |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Deployment pipeline and infrastructure requirements |
| [docs/mainnet-deployment.md](docs/mainnet-deployment.md) | Mainnet deployment record |
| [docs/testnet-deployment.md](docs/testnet-deployment.md) | Testnet deployment record |
| [docs/security-audit.md](docs/security-audit.md) | Security audit report |
| [docs/project-status.md](docs/project-status.md) | Current project status |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Development roadmap |

---

## Contributing

This project uses [conventional commits](https://www.conventionalcommits.org/):

```
feat: add batch request support
fix: correct gas limit rounding in requestHelper
docs: update SDK API reference
chore: bump SDK version to 0.2.0
security: scrub secrets from config template
```

### Commit Types

| Type       | Use |
|------------|-----|
| `feat`     | New feature |
| `fix`      | Bug fix |
| `docs`     | Documentation only |
| `chore`    | Maintenance, dependencies, build |
| `security` | Security-related changes |
| `refactor` | Code restructuring (no behavior change) |
| `test`     | Adding or fixing tests |

### Development

```bash
# Contracts
cd contracts/
forge build
forge test -vvv

# SDK
cd sdk/
npm install
npm run build
npm test

# Tyche keeper
cd tyche/
cargo build --workspace
cargo test
cargo clippy --all-targets --all-features -D warnings
cargo fmt --all
```

### Rules

- **Never commit secrets, private keys, or seeds.** Use environment variables and `config.sample.yaml` templates.
- **No third-party oracle dependencies.** Dice Protocol is a independent Robinhood Chain implementation adapted from proven commit-reveal oracle patterns.
- **Run linters before pushing** — `forge fmt`, `cargo fmt --all`, `cargo clippy`.
- **Bump versions** in `package.json` / `Cargo.toml` for releases.

---

## License

[Apache-2.0](LICENSE) — Dice Protocol is open-source software. Portions of the smart contract architecture and interfaces are adapted from Pyth Entropy / pyth-crosschain under Apache-2.0; see [NOTICE](NOTICE).

## Refunds (v10)

If a request is not revealed within about 60–90 seconds (`refundDelayBlocks = 6` L1 blocks on Robinhood/Arbitrum Nitro), the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid.
