#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/lib"
mkdir -p "$LIB"
clone_at() {
  local url="$1" sha="$2" dest="$3"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch --quiet origin "$sha"
  else
    git clone --quiet --no-checkout "$url" "$dest"
  fi
  git -C "$dest" checkout --quiet --detach "$sha"
  test "$(git -C "$dest" rev-parse HEAD)" = "$sha"
}
clone_at https://github.com/foundry-rs/forge-std.git bf647bd6046f2f7da30d0c2bf435e5c76a780c1b "$LIB/forge-std"
clone_at https://github.com/OpenZeppelin/openzeppelin-contracts.git 69c8def5f222ff96f2b5beff05dfba996368aa79 "$LIB/openzeppelin-contracts"
clone_at https://github.com/nomad-xyz/ExcessivelySafeCall.git 81cd99ce3e69117d665d7601c330ea03b97acce0 "$LIB/ExcessivelySafeCall"
printf '%s\n' 'Pinned dependencies installed and verified.'
