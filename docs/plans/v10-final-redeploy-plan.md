# Dice Protocol v10 Final Redeploy Plan

> **For Hermes:** Execute this plan task-by-task from the `dice-protocol` kanban board. Do not deploy to production without explicit Alireza approval.

**Goal:** Ship a final public-launch version of Dice Protocol with clean Pyth attribution, clean Apache-2.0 licensing, a refund path for stuck requests, a clean ABI/SDK/docs surface, and no stale v9/0.000055/publication residue.

**Architecture:** v10 keeps the proven commit-reveal/hash-chain core and Robinhood Chain deployment model, but removes launch-risk ambiguity. The contract remains immutable/no proxy, single-fee, single default provider for v1, with explicit timeout refund behavior and clean source attribution to Pyth Entropy / pyth-crosschain where derived.

**Tech Stack:** Solidity `^0.8.x`, Foundry, TypeScript SDK with ethers v6, Rust Tyche keeper, Next/Tailwind website copy, Hermes Kanban.

---

## Non-Negotiables

1. **No production deployment without explicit approval.**
2. **No secrets in diffs, logs, docs, examples, or build output.**
3. **Credit Pyth honestly. Do not erase provenance.**
4. **No proxy/upgradability.** v10 remains immutable.
5. **Keep v10 scope tight:** refund timeout, clean fee model, clean ABI/SDK/docs/license, tests, deploy rehearsal.
6. **Deploy initially with a very low nonzero fee** for live testing, then set final fee after E2E passes.
7. **Use source of truth from contract/ABI first; docs conform to code, not the other way around.**

---

## Canonical v10 Design Decisions

### Licensing and Attribution

- Repository-level license: Apache-2.0 for v10 public launch unless explicitly split by subdirectory.
- Contract headers preserve upstream attribution:
  - Pyth Entropy / pyth-crosschain
  - Apache-2.0
  - Dice-specific modifications by Dice Protocol
- Add/maintain `NOTICE` file with upstream URL and copyright.
- Public wording: “adapted from proven commit-reveal oracle patterns, including Pyth Entropy.”
- Forbidden wording: “fully original”, “zero Pyth traces”, “fork-free”, “no third-party design influence”.

### Fee Model

- Single flat protocol fee.
- `getFee(provider)` / `getFeeV2(...)` return `_state.feeInWei`.
- Request must send exact fee unless v10 intentionally changes to overpay refund. Preferred: exact fee, clear error/docs.
- Admin can call `setFee(uint128)`.
- Admin can call `withdrawFees(uint128)` to vault.
- No provider-fee revenue model in v1.

### Refund Model

Add a user-safe timeout refund for stuck requests:

```solidity
function refundRequest(address provider, uint64 sequenceNumber) external;
```

Rules:
- Request must be active.
- `msg.sender` must be the original requester.
- Timeout must have elapsed.
- Request fee is removed from accrued fees.
- Request is cleared.
- Fee is returned to requester.
- Emit `RequestRefunded(provider, requester, sequenceNumber, amount, extraArgs)`.

Timeout source:
- Prefer block-based timeout for deterministic chain behavior: `refundDelayBlocks`.
- If using timestamp, document L2 sequencer assumptions.
- Admin can set timeout only within bounded range, or timeout is immutable constructor parameter.

### Callback Semantics

Docs and tests must exactly match source:
- Callback revert with sufficient remaining gas: reveal emits `Revealed(... callbackFailed=true ...)`, request remains retryable if that is intended.
- Insufficient gas path can revert with `InsufficientGas()` unless v10 redesigns this.
- No broad “callback always succeeds” wording.

### ABI/SDK Surface

SDK must expose only working v10 methods:
- `getDefaultProvider`
- `getFee`
- `getProviderInfo`
- `getRequest`
- `getAccruedFees` / `getAccruedTreasuryFees` only if both are supported and documented
- `getProtocolFee`
- `requestRandom`
- `revealWithCallback`
- `refundRequest`
- admin-only `registerFor`, `withdrawFees`, `setFee`, `setDefaultProvider` if included

Remove or rename broken SDK helpers:
- `registerProvider()` must not call nonexistent `register()`.
- `withdrawFees()` must not call disabled `withdraw()`.

---

## Task Plan

### Task V10-001: Freeze current state and create v10 branch

**Objective:** Preserve current work and isolate v10.

**Files:** repo-level git state.

**Steps:**
1. Inspect `git status --short`.
2. Ensure the existing backup zip exists under `/root/dice-protocol/backups/`.
3. Create branch `feat/dice-v10-final` from current working tree or after committing current doc cleanup.
4. Do not push.

**Verify:** `git branch --show-current` returns `feat/dice-v10-final`.

---

### Task V10-002: Finalize license and NOTICE

**Objective:** Make licensing legally honest and launch-clean.

**Files:**
- `LICENSE`
- `NOTICE`
- contract headers under `contracts/src/**/*.sol`
- `README.md`
- `docs/whitepaper.md`
- `sdk/package.json`

**Steps:**
1. Replace repo-level MIT license with Apache-2.0 unless a deliberate mixed-license layout is chosen.
2. Add `NOTICE` crediting Pyth Entropy / pyth-crosschain.
3. Update contract headers with clear attribution.
4. Update README/docs license sections.
5. Update SDK package license if repo-wide Apache-2.0 is chosen.

**Verify:**
- Search for `MIT` and classify any remaining usage.
- Search for `fully original`, `zero Pyth`, `Douro`, `dourolabs` and ensure zero active public hits.
- Search for `Pyth Entropy` and confirm credit exists in appropriate places.

---

### Task V10-003: Clean contract comments and public source residue

**Objective:** Remove stale v9 comments and old fee references from source.

**Files:**
- `contracts/src/DiceEntropy.sol`
- `contracts/src/sdk/*.sol`

**Steps:**
1. Remove `0.000055` from all comments.
2. Avoid hardcoding `0.000025` in contract comments except tests/examples.
3. Make comments describe source behavior, not historical intent.
4. Keep Pyth attribution.

**Verify:** `grep -R "0.000055\|55000000000000" contracts/src` returns zero.

---

### Task V10-004: Design refund state changes

**Objective:** Specify minimal state needed for timeout refund.

**Files:**
- `contracts/src/sdk/DiceStructsV2.sol`
- `contracts/src/DiceEntropy.sol`
- tests under `contracts/test/`

**Steps:**
1. Confirm current `Request` has enough data: requester, blockNumber, callbackStatus, provider, sequenceNumber.
2. Decide whether fee amount needs storage. Since fee is flat but can change later, store `feePaid` per request if refund may happen after fee changes.
3. Add `uint128 feePaid` if needed, understanding storage/gas tradeoff.
4. Add refund timeout storage/config.

**Verify:** Storage layout compiles and tests cover fee changes before refund.

---

### Task V10-005: Implement refundRequest

**Objective:** Add user refund for stuck active requests.

**Files:**
- `contracts/src/DiceEntropy.sol`
- `contracts/src/sdk/IEntropy.sol` or v10 interface
- `contracts/src/sdk/DiceEventsV2.sol`
- `contracts/src/sdk/DiceErrors.sol`

**Steps:**
1. Add custom errors if needed:
   - `RefundNotAvailable()`
   - `RefundUnauthorized()` if not using `Unauthorized()`
2. Add event:
   - `RequestRefunded(address indexed provider, address indexed requester, uint64 indexed sequenceNumber, uint128 amount, bytes extraArgs)`
3. Implement `refundRequest(provider, sequenceNumber)`.
4. Clear request before external transfer.
5. Decrement accrued fees safely.
6. Transfer ETH to requester using `.call` and require success.

**Verify:** Foundry tests for success and all failure paths.

---

### Task V10-006: Clean ABI surface or clearly disable legacy functions

**Objective:** Ensure public ABI and SDK do not advertise dead paths as usable.

**Files:**
- `contracts/src/sdk/IEntropy.sol`
- `contracts/src/sdk/IEntropyV2.sol`
- `contracts/src/DiceEntropy.sol`
- `sdk/src/index.ts`
- docs

**Steps:**
1. Decide whether legacy compatibility methods remain in ABI.
2. If retained, docs/SDK must mark unsupported methods as reverting.
3. SDK must not expose wrappers for disabled methods as normal usable helpers.
4. Rename SDK admin methods to match actual contract functions.

**Verify:** SDK contract calls all exist in ABI and do not call known-reverting methods unless explicitly named unsupported.

---

### Task V10-007: Foundry tests for fee behavior

**Objective:** Lock exact fee behavior.

**Tests:**
- Exact fee succeeds.
- Underpay reverts `InsufficientFee()`.
- Overpay behavior is explicitly tested: either reverts or refunds excess, depending final design.
- `setFee()` updates future requests only.
- Old request refund returns fee paid at request time, not current fee.

**Verify:** `forge test --match-test Fee` passes.

---

### Task V10-008: Foundry tests for refund behavior

**Objective:** Prove stuck-request refund works.

**Tests:**
- Cannot refund before timeout.
- Non-requester cannot refund.
- Requester can refund after timeout.
- Refund clears request.
- Refund decrements accrued fees.
- Refund emits event.
- Reveal after refund reverts `NoSuchRequest()`.

**Verify:** `forge test --match-test Refund` passes.

---

### Task V10-009: Foundry tests for callback behavior

**Objective:** Make callback semantics exact.

**Tests:**
- Successful callback clears request.
- Callback revert records `callbackFailed=true` according to chosen behavior.
- Insufficient gas path matches docs.
- Retry behavior works if retryable.

**Verify:** `forge test --match-test Callback` passes.

---

### Task V10-010: Full contract test gate

**Objective:** Confirm no regression.

**Commands:**
```bash
cd /root/dice-protocol/contracts
forge fmt --check
forge build
forge test
```

**Verify:** all pass.

---

### Task V10-011: Regenerate ABI and SDK artifacts

**Objective:** Ensure SDK uses v10 ABI.

**Files:**
- `sdk/src/abi.json`
- `sdk/dist/abi.json`
- `sdk/src/index.ts`
- `sdk/src/test.ts`
- `sdk/package.json`

**Steps:**
1. Copy ABI from Foundry artifact to SDK source.
2. Ensure `npm run build` copies `src/abi.json` to `dist/abi.json`.
3. Update SDK methods for v10.
4. Add assertions in smoke tests for fee, ABI functions, and refund method presence.

**Verify:**
```bash
cd /root/dice-protocol/sdk
npm run build
npm test
```

---

### Task V10-012: Update Tyche keeper compatibility

**Objective:** Ensure keeper works with v10 ABI/address without changing core runtime unnecessarily.

**Files:**
- `tyche/` configs and ABI references
- keeper tests

**Steps:**
1. Search for old ABI/function assumptions.
2. Update generated bindings if applicable.
3. Ensure keeper still calls `revealWithCallback` correctly.
4. Ensure refund path does not require keeper participation.

**Verify:**
```bash
cd /root/dice-protocol/tyche
cargo test
cargo build --release
```

---

### Task V10-013: Deploy rehearsal with tiny nonzero fee

**Objective:** Deploy v10 to target chain for live testing with a tiny nonzero fee.

**Initial fee:** `1 wei` unless tests require another tiny value.

**Requires approval before broadcast.**

**Steps before approval:**
1. Prepare deploy script with env validation.
2. Generate fresh hash chain commitment.
3. Simulate/deploy dry-run if possible.
4. Present constructor args without secrets.

**Blocked until:** Alireza explicitly approves broadcast.

---

### Task V10-014: Live v10 E2E test at tiny fee

**Objective:** Prove deployed v10 works before final fee.

**Tests:**
- `getFee` returns tiny fee.
- Request succeeds with exact tiny fee.
- Reveal/callback succeeds.
- Refund succeeds on intentionally unrevealed request after timeout.
- Admin withdraw works after successful request.
- Block explorer/source verification complete.

**Verify:** collect tx hashes and on-chain reads. Do not expose private keys or RPC secrets.

---

### Task V10-015: Set final fee after E2E

**Objective:** Move from test fee to production fee.

**Final fee:** `25000000000000` wei (`0.000025 ETH`).

**Requires approval before transaction.**

**Verify:** `getFee(defaultProvider)` returns `25000000000000`.

---

### Task V10-016: Update all public launch surfaces to v10

**Objective:** Replace v9 with v10 everywhere public.

**Files:**
- `README.md`
- `docs/*.md`
- `sdk/SKILL.md`
- `sdk/README.md`
- website pages under `/root/dice-protocol-web/app`
- `AGENTS.md`
- package metadata

**Verify searches:**
- old v9 address zero active hits except internal historical notes
- old fee residue zero active hits
- `0.000055` zero active hits
- Pyth attribution present
- refund behavior documented
- SDK examples compile

---

### Task V10-017: Final launch-readiness verification

**Objective:** Confirm v10 is launch-ready.

**Commands:**
```bash
cd /root/dice-protocol/contracts && forge build && forge test
cd /root/dice-protocol/sdk && npm run build && npm test
cd /root/dice-protocol/tyche && cargo test
```

**Also verify:**
- Active public-surface stale scan passes.
- Kanban v10 cards complete.
- No secrets in diffs.
- No production deploy/publish without approval.

---

## Risk Register

| Risk | Mitigation |
|---|---|
| Refund storage/gas increase | Add tests and compare gas snapshots before/after |
| License confusion | Use Apache-2.0 repo-wide and add NOTICE |
| SDK drift from ABI | Build copies ABI, smoke test asserts function presence |
| Docs drift after v10 | Final active-surface scan before launch |
| Accidental production deploy | Kanban tasks V10-013/V10-015 blocked pending explicit approval |

---

## Definition of Done

v10 is done only when:
- Contract source has no stale fee/comment residue.
- Pyth attribution and Apache-2.0 licensing are correct.
- Refund timeout exists and is tested.
- Fee behavior is explicit and tested.
- SDK methods match ABI and smoke tests pass.
- Keeper compatibility is verified.
- Public docs/site match v10.
- Live E2E passes at tiny fee.
- Final fee is set only after approval.
- No open v10 kanban cards remain.
