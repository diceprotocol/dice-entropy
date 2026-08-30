# Robinhood Chain Testnet Reproducible Release

This release freezes the DiceEntropy build inputs used for the replacement Robinhood Chain testnet deployment.

## Build inputs

- Solidity: `0.8.24+commit.e11b9ed9`
- EVM version: `cancun`
- Optimizer: enabled, 200 runs
- viaIR: `true`
- Metadata bytecode hash: `ipfs`
- CBOR metadata: enabled
- Literal source content: disabled
- forge-std: `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`
- OpenZeppelin Contracts: `69c8def5f222ff96f2b5beff05dfba996368aa79`
- ExcessivelySafeCall: `81cd99ce3e69117d665d7601c330ea03b97acce0`

## Reproduce

```bash
cd contracts
bash scripts/reproduce-release.sh
```

The script clones every dependency at its exact SHA, performs a clean build, and prints creation/runtime byte lengths and Keccak hashes.

The deployment manifest is completed only after the onchain runtime hash matches this clean build exactly. No secret seed or private configuration belongs in this repository.
