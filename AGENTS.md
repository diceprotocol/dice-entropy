# Dice Protocol — Trustless RNG Oracle

## Status

- **Stage:** v10 live on Robinhood Chain mainnet
- **Environment:** Production — immutable contracts, no proxy
- **Goal:** Public launch surface aligned to live v10
- **DiceEntropy:** `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`
- **Fee:** `0.000025 ETH` exact
- **Refund delay:** `6` L1 blocks (~60–90s)
- **Next:** Admin wallet should call `acceptAdmin()` for `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD` (proposeAdmin already submitted)

## Architecture

Dice Protocol is a trustless commit-reveal randomness oracle for Robinhood Chain (Arbitrum Nitro L2, chain ID 4663). Delivers cryptographically secure, unbiased on-chain random numbers via a hash-chain commitment scheme. User-contributed randomness + provider-revealed values via Keccak256 — manipulation-resistant as long as either party is honest.

**Contracts (immutable, no proxy, no upgrade path):**
- DiceEntropy: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`
- Keeper (Tyche): `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6`
- Admin: `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD`
- Vault: `0x918EAF0b2589710B0D85ef48C12a343E68263841`

**Chain Config:**
- Chain ID: 4663 (mainnet), 46630 (testnet)
- RPC (public): `https://rpc.mainnet.chain.robinhood.com` — HTTP only, 190ms avg latency, NO WebSocket support. NOTE: the public endpoint DOES enforce rate limits (HTTP 429) under sustained polling — it load-balances to internal backend nodes (10.31.x.x:8547) that reject/time out under load. Keeper throttles batch RPC calls (BATCH_THROTTLE=150ms) and uses a 20-block re-scan overlap (not 100) to stay under the limit. For production scale, move keeper block-polling to a dedicated RPC (Alchemy key or self-hosted node).
- `eth_getLogs` works reliably — detects events shortly after tx mining. Prior reports of long indexing delay were traced to reverted test transactions, not RPC indexing.
- Alchemy WS `subscribe_logs` also works (~2.9s, same as HTTP polling). No measurable speed advantage of WS over HTTP polling.
- Fee: 0.000025 ETH per request (mainnet, live on-chain), 0 ETH (testnet free tier)
- Refund delay: 6 L1 blocks (~60–90s wall-clock on Robinhood/Arbitrum Nitro)
- Chain depth: 1,000 hashes currently registered on live v10 mainnet (can be rotated/extended via registerFor)

**Subprojects:**
- `contracts/` — Solidity (Foundry): DiceEntropy.sol, DiceState.sol, TestConsumer.sol
- `tyche/` — Rust keeper service (Axum + SQLx, SQLite by default), auto-reveals hash chain values on-chain
- `sdk/` — TypeScript SDK for consumers
- Website: diceprotocol.world — Next.js + Tailwind at `/root/dice-protocol-web/`

## Build & Deploy Commands

### Contracts (Foundry)
```bash
cd /root/dice-protocol/contracts
forge build
forge test
forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
```

### Website
```bash
cd /root/dice-protocol-web
rm -rf .next out && npm run build
cp -r out/* <deployment-target>
```

### Tyche Keeper
See `tyche/AGENTS.md` for Rust-specific build commands and code conventions.

## Code Conventions

- **Solidity:** Foundry, version 0.8.24, Slither + Aderyn for audits (all clean)
- **Git:** Conventional commits — `type(scope): summary` (`fix(lazer)`, `chore(contract-manager): ...`), imperative subjects ≤72 chars
- **Secrets:** Central secrets vault at `[REDACTED_SECRETS_VAULT]/` is the single source of truth. Source the central secrets vault at runtime; never duplicate keys into project .env files.
- **Security:** Never commit `config.yaml`, `.env`, or signing credentials. Each replica uses unique keeper credentials. Only fee-managing instances hold fee-manager credentials.

## Website Style Guide

**Reference component:** The `CodeBlock` card on the SDK page (`app/sdk/page.tsx`) is the source of truth for all card/container styling.

**Container/card style (unified across ALL pages):**
- Outer: `border border-gray-800 rounded-lg overflow-hidden`
- Header bar: `px-4 py-3 border-b border-gray-800 bg-black/60`
- Body: `bg-black/40` or `bg-black/60` (transparent, shows dither shader through)
- Never use `bg-gray-900` or solid `bg-black` on cards — these hide the background shader
- Never use `border-gray-700` — use `border-gray-800` everywhere

**Page layout:**
- Main wrapper: `<main className="relative z-10 pt-32 pb-24 px-6 min-h-screen">`
- Content container: `<div className="max-w-3xl mx-auto">`
- Section spacing: `space-y-8` between sections
- Always `pt-32` (not `pt-16` or `pt-24`) for consistent top padding

**Code blocks:**
- Label bar with filename: `text-xs font-mono text-gray-500`
- Code text: `text-xs sm:text-sm font-mono text-gray-300`
- Background: `bg-black/40` (transparent)

**Buttons:**
- Primary: `px-8 py-3.5 bg-white text-black font-medium text-sm hover:bg-gray-200 transition-colors`
- Secondary (bordered): `px-8 py-3.5 border border-white font-medium text-sm hover:bg-white hover:text-black transition-colors`
- Text links: `text-gray-500 hover:text-white transition-colors`
- Bordered buttons stay sharp (no rounded corners). All other containers use `rounded-lg`.

**Tables:**
- `border border-gray-800 rounded-lg overflow-hidden`
- Header: `bg-black/60`
- Row separators: `border-t border-gray-800`
- Cell padding: `p-3` or `p-4`

**Lists (bullet points):**
- Bullet: `<span className="mt-1.5 w-1 h-1 rounded-full flex-shrink-0 bg-white"></span>`
- Text: `text-sm text-gray-400 leading-relaxed`

**Never do:**
- Card grids with `gap-px bg-gray-800/30` — looks terrible
- Different border colors on different pages
- Solid backgrounds that hide the dither shader
- Inconsistent top padding between pages

## Testing

- Contracts: `forge test` (unit + fuzz tests in `contracts/test/`)
- Keeper: `cargo test` in `tyche/` (see tyche/AGENTS.md)
- Audits passed: Slither + Aderyn clean (0 critical findings)

## Key Paths

- Contracts: `/root/dice-protocol/contracts/src/`
- Keeper: `/root/dice-protocol/tyche/` (see `tyche/AGENTS.md` for details)
- SDK: `/root/dice-protocol/sdk/`
- Website: `/root/dice-protocol-web/`
- Deploy scripts: `/root/dice-protocol/contracts/script/`
- Audit reports: `/root/dice-protocol/AUDIT_*.md`, `SECURITY_*.md`, `SlitherReport.md`

## Kanban Board

- **Hermes Kanban:** `dice-protocol` (38 done, 24 ready, 3 todo)
- Switch board: `hermes kanban boards switch dice-protocol`