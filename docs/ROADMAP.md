# Dice Protocol  - Roadmap

## Current State (July 2026)

### Shipped
- DiceEntropy **v10** live on Robinhood Chain mainnet (`0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`)
- Exact fee: `0.000025 ETH` (`25000000000000` wei) via `getFeeV2()`
- Tyche keepers operational (auto-reveal verified)
- TypeScript SDK: `@diceprotocol/sdk`
- **500,000-value** hash chain registered on live v10
- E2E verified: request → auto-reveal → random number delivered
- **$DICE** live and graduated on pons (Robinhood Chain)
  - CA: `0x3f9f0b6073ee8c495aed96869af31850fed40feb`
  - Supply: 1,000,000,000
- **x402 agent API** live: fixed **$0.05 USDG** via Primer (`eip155:4663`)
  - `POST https://diceprotocol.world/x402/v1/random`
  - Info: `https://diceprotocol.world/x402/v1/info`
- **$DICE staking** live (score → free daily x402 credits)
  - DiceStake: `0xc091ce59cAC1112A30e4344ced039c25B6cfa174`
  - DiceQuota: `0x825AC2A5Ca8D8A6E56dF418C3227a72bD39830F3`
  - Tiers: 100k → 50/day, 1M → 150/day, 10M → 400/day, 10M+30d lock → 1000/day
  - Stake UI: https://diceprotocol.world/stake

### Security posture (honest)
- Contract review to date is **internal + automated** (Slither and operational review).
- **No independent third-party audit firm report** has been published for v10.
- Historical pre-v10 ops issue (keeper credential exposure) was mitigated before current public surfaces.
- Treat `security-audit.md` as internal/automated notes, not a substitute for an external audit.

## Next  - Hardening
- [x] Private Robinhood RPC for keeper ops (primary path)
- [ ] Multi-key RPC rotation and failover polish
- [ ] Proof explorer: request → reveal → hash-chain verify in one view
- [ ] Public latency and uptime metrics (p50/p95 reveal time, keeper health)
- [ ] Stake UX polish and builder subscription playbooks
- [ ] Multi-replica Tyche (redundancy  - 2+ keepers for failover)
- [ ] Alerting on keeper downtime

## Builder platform
- [x] npm `@diceprotocol/sdk`
- [x] x402 pay-per-randomness (fixed $0.05 USDG)
- [ ] React hook (`useDiceRandom()`)
- [ ] Webhooks for Requested / Revealed
- [ ] Integrator dashboard: usage, remaining chain capacity, recent reveals
- [ ] Solidity + agent templates for one-call randomness consumers
- [ ] Example dApp repository (coin flip, lottery, NFT mint)

## Network
- [x] $DICE staking Phase 1+2 (score + on-chain quota → free x402 credits)
- [ ] Protocol fee use (buyback/burn or other) - exploratory only, not committed
- [ ] Multi-provider support (more than one reveal path)
- [ ] Keeper marketplace / bonded keepers for higher assurance
- [ ] Governance over fee and provider parameters via stake

## Later  - Expansion
- [ ] Onchain game primitives (raffle, shuffle, fair mint helpers)
- [ ] Agent kits: request → act → settle loops on Robinhood
- [ ] Deeper Robinhood ecosystem integrations
- [ ] Selective multi-chain only after Robinhood density is real
- [ ] Hash chain renewal automation (alert before exhaustion)

## Principles
- Ship reliability before narrative
- Token utility must map to real capacity (today: free x402 credits from stake score)
- Stay Robinhood-native first
- No fake launch dates  - phases over calendars
- Docs must match live chain (addresses, chain length, fees, products)

## Non-goals (current oracle core)
These apply to **DiceEntropy** itself, not the wider product surface:
- ❌ Upgradable entropy contract  - v10 is immutable for trust
- ❌ Oracle fees in $DICE  - oracle fee remains exact native ETH; agents may pay USDG via x402 gateway
- ❌ Multi-provider entropy (yet)  - single exclusive provider for current v10 ops
- ❌ Independent third-party audit claim until one is completed and published

## Agent path (x402)
- `POST https://diceprotocol.world/x402/v1/random`  - fixed **$0.05 USDG** (Primer, Robinhood Chain `eip155:4663`)
- `GET https://diceprotocol.world/x402/v1/info`  - human-readable endpoint summary
- USDG: `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
- Facilitator: `https://x402.primer.systems`
- payTo: Admin `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD`
- Free path for stakers: `POST /x402/v1/random/free` (wallet signature + DiceQuota credits)
- On-chain path unchanged: exact ETH `getFeeV2()` fee to DiceEntropy v10

## Official links
- Site: https://diceprotocol.world
- Stake: https://diceprotocol.world/stake
- Docs: https://diceprotocol.world/docs
- Token: https://diceprotocol.world/token
- Status: https://diceprotocol.world/status
