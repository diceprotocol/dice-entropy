# Tyche Keeper — Rust Auto-Reveal Service

Part of Dice Protocol. See `/root/dice-protocol/AGENTS.md` for protocol-level context (contracts, chain config, addresses, deploy).

## Build & Test Commands

- `cargo build --workspace`: compile the web service and helper binaries.
- `cargo test [-- --nocapture]`: run unit/integration suites, optionally showing logs.
- `RUST_LOG=INFO cargo run -- run`: start the local server using `config.yaml`.
- `cargo run -- setup-provider`: register the randomness provider specified in the config.
- `cargo sqlx migrate run` or `database reset`: apply or reset schema using the `.env` `DATABASE_URL`.
- `./check-sqlx.sh`: ensure SQLx offline metadata is current before DB-affecting commits.
- `cli start | cli test | cli fix`: Nix-shell shortcuts for watch, verify, and autofix loops.

## Code Conventions

- `cargo fmt --all` + `cargo clippy --all-targets --all-features -D warnings` (4-space indent, trailing commas, no lint debt).
- Naming: modules and files use `snake_case`, public structs/enums use `PascalCase`, constants use `SCREAMING_SNAKE_CASE`.
- Secrets: reference via env vars, never literals. Derive from `config.sample.yaml`. Never commit `config.yaml` or `.env`.
- Bump `Cargo.toml` version on changes. Run `cargo check` to update `Cargo.lock`.

## Testing

Keep module-level tests inside the relevant file (`#[cfg(test)]` blocks) and add `tests/` integration suites for CLI flows or keeper orchestration. Run `cargo sqlx migrate run` after editing migrations so `cargo test` interacts with the right schema. Prioritize coverage on chain adapters, keeper scheduling, replica assignment, and API pagination — mock RPC traits to avoid network flakiness.

## Module Layout

- `src/api/` — HTTP routes (Axum)
- `src/chain/` — Blockchain adapters
- `src/keeper/` — Reveal loops
- `src/command/` — CLI verbs
- `src/lib.rs` — Shared types
- `src/main.rs` — Entry point
- `migrations/` — SQLx schema migrations
- `config.sample.yaml` — Configuration template