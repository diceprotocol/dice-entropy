# Dice Protocol Core Repository

## Status

- **Stage:** DiceEntropy v10 is live on Robinhood Chain mainnet. Reproducible replacement testnet deployment is live and Blockscout-verified.
- **Environment:** This public GitHub repository contains the immutable v10 contract source, SDK snapshot, reference keeper source, examples, and public documentation. Live operations use separate private configuration.
- **Goal:** Keep every active public file aligned to deployed v10 and avoid exposing operational details.
- **Next step:** Daily public consistency watchdog is live. npm `1.0.3` remains unpublished pending explicit package-release approval.

## Architecture

- Mainnet chain ID: `4663`.
- Mainnet DiceEntropy v10: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.
- Mainnet provider: `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6`.
- Exact mainnet protocol fee: `25000000000000` wei (`0.000025 ETH`).
- Refund delay: `6` L1 blocks, approximately 60 to 90 seconds.
- Live registered hash-chain span: 500,000 values (`3` through `500003`).
- Testnet chain ID: `46630`.
- Testnet DiceEntropy: `0x43c8A7B1a85384cabf3D3Fd45a15C01F5b51A42D`.
- Testnet provider: same provider address as mainnet.
- Exact testnet fee: `0.000025 ETH`.
- Package: `@diceprotocol/sdk`.
- Public review status: internal and automated review only. No third-party audit firm report has been published for v10.

## Build & Deploy

```bash
cd /root/dice-entropy/contracts
/root/.foundry/bin/forge build
/root/.foundry/bin/forge test

cd /root/dice-entropy/sdk
npm ci
npm run build
npm test
```

Production contract or keeper changes require explicit human approval. Documentation publication also requires approval because it changes public content.

## Code Conventions

- Solidity 0.8.24 and Apache-2.0 licensing.
- Conventional commits.
- Public copy uses `onchain`, avoids unsupported absolutes, and contains no infrastructure or credential details.
- Samples must pay the exact live fee returned by `getFeeV2`.
- Never commit secrets, live RPC credentials, hash-chain seeds, or private operational configuration.

## Testing

- Contract: Foundry build and test suite.
- SDK: npm build and tests.
- Documentation: stale-constant scanner, link checks, and diff check.
- Verify contract functions and values against live RPC and verified Blockscout ABI.
- Verify testnet address and bytecode against chain ID 46630.

## Key Paths

- `contracts/src/DiceEntropy.sol`
- `contracts/src/sdk/`
- `sdk/`
- `docs/`
- `README.md`
- `tyche/`

## Kanban Board

- Hermes board: `dice-protocol`.
