#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/root/.foundry/bin:$PATH"
cd "$ROOT"
bash scripts/install-pinned-deps.sh
forge clean
forge build --force
ART=out/DiceEntropy.sol/DiceEntropy.json
creation="$(jq -r '.bytecode.object' "$ART")"
runtime="$(jq -r '.deployedBytecode.object' "$ART")"
creation_hash="$(cast keccak "0x$creation")"
runtime_hash="$(cast keccak "0x$runtime")"
solc_line="$(solc --version | grep '^Version:')"
printf 'commit=%s\n' "$(git -C "$ROOT/.." rev-parse HEAD)"
printf 'compiler=%s\n' "$solc_line"
printf 'creation_bytes=%s\n' "$(( ${#creation} / 2 ))"
printf 'creation_keccak=%s\n' "$creation_hash"
printf 'runtime_bytes=%s\n' "$(( ${#runtime} / 2 ))"
printf 'runtime_keccak=%s\n' "$runtime_hash"
printf 'metadata_ipfs=%s\n' "$(jq -r '.metadata' "$ART" | jq -r '.settings.metadata.bytecodeHash')"
