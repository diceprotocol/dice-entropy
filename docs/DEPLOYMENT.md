# Dice Protocol — Deployment Guide

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- [Rust](https://rustup.rs/) (for Tyche keeper)
- [Node.js](https://nodejs.org/) 18+ (for SDK)
- Robinhood Chain wallet with ETH for gas

## Contract Deployment

### 1. Generate Hash Chain

```python
from Crypto.Hash import keccak
import secrets, json

seed = secrets.token_bytes(32)
chain = []
current = seed
for _ in range(500000):
    k = keccak.new(digest_bits=256); k.update(current); current = k.digest()
    chain.append(current)

commitment = chain[-1]  # Root hash
print(f"Seed: 0x{seed.hex()}")
print(f"Commitment: 0x{commitment.hex()}")

# Save seed securely (NEVER commit to git)
with open('secrets/hash-chain-50k.json', 'w') as f:
    json.dump({"seed": seed.hex(), "commitment": commitment.hex(), "length": 1000}, f)
```

### 2. Generate Commitment Metadata

The contract stores bincode-serialized metadata containing the seed and chain length:

```python
import struct

seed_hex = "[REDACTED_SEED]"
seed = bytes.fromhex(seed_hex)
chain_length = 1000

# bincode format: raw struct (seed[32] + chain_length[u64 LE])
metadata = b''  # EMPTY — seed stored locally in keeper config only, never onchain
print(f"Metadata: 0x{metadata.hex()}")  # 40 bytes, no length prefix
```

### 3. Deploy Contract

```bash
forge create src/DiceEntropy.sol:DiceEntropy \
  --rpc-url "https://rpc.mainnet.chain.robinhood.com" \
  --private-key "$ADMIN_PK" \
  --constructor-args \
    "$ADMIN_ADDR" \           # admin
    "25000000000000" \         # fee (0.000025 ETH)
    "$KEEPER_ADDR" \           # defaultProvider
    false \                    # prefillRequestStorage
    "$VAULT_ADDR" \            # vault
    "$COMMITMENT" \            # providerCommitment (hash chain root)
    1000 \                       # providerChainLength (live v10; longer supported)
    "$METADATA_HEX" \          # providerCommitmentMetadata (40 bytes)
  --broadcast
```

### 4. Set Gas Limit

```bash
cast send "$CONTRACT" "setDefaultGasLimit(uint32)" 100000 \
  --rpc-url "https://rpc.mainnet.chain.robinhood.com" \
  --private-key "$KEEPER_PK"
```

### 5. Verify on Blockscout

```bash
forge verify-contract "$CONTRACT" \
  src/DiceEntropy.sol:DiceEntropy \
  --verifier blockscout \
  --verifier-url "https://robinhoodchain.blockscout.com/api"
```

## Tyche Keeper Deployment

### 1. Build

```bash
cd tyche
cargo build --release
```

### 2. Configure

Copy `config/dice-config.sample.yaml` to `config/dice-config.yaml` and fill in:

```yaml
provider:
  address: "0x8741..."        # Keeper address
  secret:
    value: "<seed_hex>"        # Hash chain seed (NO 0x prefix)
  chain_length: 1000  # live v10 registration; increase when rotating

keeper:
  signing_credential:
    value: "[REDACTED]"        # Keeper signing credential

chains:
  4663:
    geth_rpc_addr: "https://rpc.mainnet.chain.robinhood.com"
    contract_addr: "0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c"
    reveal_delay_blocks: 0
    confirmed_block_status: "Latest"
    gas_limit: 500000

api:
  host: "0.0.0.0"
  port: 34000
```

### 3. Initialize Database

```bash
export DATABASE_URL="sqlite:///root/dice-protocol/data/tyche.db"
sqlx database create
sqlx migrate run
```

### 4. Install as systemd Service

```bash
cp tyche/dice-tyche.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable dice-tyche
systemctl start dice-tyche
```

### 5. Verify

```bash
systemctl status dice-tyche
# Should show: active (running)

# Check logs
journalctl -u dice-tyche -f --no-pager
# Should show: "Processing" and "Processed" messages with block numbers
```

## Post-Deployment Checklist

- [ ] Contract has code (`cast code $CONTRACT`)
- [ ] Provider registered (`getProviderInfo`)
- [ ] Consumer examples pass explicit callback gas (example: 200000)
- [ ] Tyche service running (`systemctl is-active dice-tyche`)
- [ ] Tyche processing blocks (check logs for block numbers advancing)
- [ ] E2E test: send a request, verify Tyche auto-reveals
- [ ] Keeper wallet funded with enough ETH for gas
- [ ] Config file gitignored
- [ ] Private keys not in git
