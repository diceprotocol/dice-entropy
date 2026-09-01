# CoinFlip example (NON-PRODUCTION)

Reference consumer for Dice Protocol. It is an example, not a live game and not a recommended casino.

This tree is self-contained relative to the `dice-entropy` repo:

- Oracle fee is queried via `getFeeV2` and is **not** the wager.
- Player sends `fee + wager`. Only `fee` is forwarded to DiceEntropy.
- Wager is escrowed on CoinFlip.
- Wins credit a **pull** payout of `2 * wager`. The callback never sends ETH.
- House must pre-fund the contract. `receive()` accepts bankroll.
- `nonReentrant` on `flip`, `withdraw`, and `withdrawBankroll`.

## Build and test

From this directory, with Foundry and git submodules initialized at the repo root (`git submodule update --init --recursive`):

```bash
cd examples/coin-flip
forge test -vv
```

Expected: all tests pass. `foundry.toml` remaps to in-repo `../../sdk` and `../../contracts`.

## How payment works

```
msg.value  ==  getFeeV2(provider, 200000)  +  wager
               \________________________/     \___/
                     sent to Dice           stays here
```

A win credits `pendingPayouts[player] += 2 * wager`. The player calls `withdraw()`.

## Frontend

`frontend/index.html` is a local demo UI. It is **not production**.

1. Deploy `CoinFlip` yourself (testnet only).
2. Open the HTML file (or any static server).
3. Paste the CoinFlip address.
4. Connect a wallet on Robinhood Chain testnet (46630).
5. Fund the CoinFlip bankroll, then flip.

Do not point this UI at a mainnet CoinFlip. There is no deployed production CoinFlip.

## Files

| Path | Role |
|------|------|
| `contracts/CoinFlip.sol` | Example consumer |
| `test/CoinFlip.t.sol` | Unit tests against a fee-exact mock |
| `test/CoinFlipDiceEntropy.t.sol` | Compiles and exercises in-repo DiceEntropy |
| `frontend/index.html` | Non-production demo UI |
