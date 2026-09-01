# DiceEntropy v10 Release Provenance

This document records the reproducibility and deployment inputs for DiceEntropy v10.

## Mainnet

- Chain ID: `4663`
- Contract: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`
- Provider: `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6`
- Protocol fee: `25000000000000` wei
- Source release: public repository commit `2fc3ba2`
- Compiler: Solidity `0.8.24+commit.e11b9ed9`
- EVM version: Cancun
- Optimizer: enabled, 200 runs
- IR pipeline: enabled
- Bytecode metadata hash: IPFS
- Dependencies: forge-std and OpenZeppelin revisions pinned in `contracts/foundry.lock`; ExcessivelySafeCall pinned by commit in the release build manifest

## Robinhood Chain testnet replacement

- Chain ID: `46630`
- Contract: `0x43c8A7B1a85384cabf3D3Fd45a15C01F5b51A42D`
- Deployment transaction: `0x90f5bc8d5974979ac8b6b9925af2f65ee5f7901a7dedeb05bfb2b989ae2c2d60`
- Protocol fee: `25000000000000` wei
- Refund delay: `6` blocks
- Default callback gas: `200000`
- Runtime hash: `0x53e734c29c90ad021b6e3e1c388355b1f820f80f0e6635409ef26620038605b1`
- Source: public reproducible release artifacts attached to the deployment remediation record
- Compiler: Solidity `0.8.24+commit.e11b9ed9`
- EVM version: Cancun
- Optimizer: enabled, 200 runs
- IR pipeline: enabled
- Bytecode metadata hash: IPFS

## Reproduction gate

A release is reproducible only when two isolated clean builds produce the same runtime artifact hash and that hash matches the deployed runtime after source verification. Compiler timing, filesystem paths, and build-directory names are excluded from the comparison.

Use the pinned dependency installer and reproduction script under `contracts/scripts/` before publishing a new deployment manifest.

## Immutability and migration

DiceEntropy deployments are immutable. A new address does not disable an older deployment. During any future cutover, keep the prior reveal lane active until all accepted requests are terminal and the defined quiet period has elapsed.
