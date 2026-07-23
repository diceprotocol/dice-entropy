//! Alchemy minedTransactions watcher via Python sidecar.
//!
//! The Python websockets library reliably receives alchemy_minedTransactions
//! pushes on Robinhood Chain. tokio-tungstenite (Rust) mysteriously receives
//! zero messages inside the keeper process despite identical params.
//! Rather than fight the Rust WS stack, we spawn a Python sidecar that
//! subscribes to all mined txs, filters for requestV2 to our contract,
//! and writes JSON lines to stdout. This module reads stdout and forwards
//! block ranges to the processor channel.
//!
//! Latency: ~250ms from tx mined to block range sent.

use crate::keeper::block::BlockRange;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tracing;

/// Reconnect delay when the sidecar exits.
const RECONNECT_DELAY: Duration = Duration::from_secs(2);

/// Path to the Python sidecar script.
const SIDECAR_SCRIPT: &str = "scripts/mined_tx_watcher.py";

/// Watch for mined requestV2 transactions via the Python sidecar.
///
/// Spawns `python3 scripts/mined_tx_watcher.py`, reads JSON lines from stdout,
/// and forwards block ranges to `tx`. Auto-restarts on exit.
pub async fn watch_mined_transactions(
    ws_url: &str,
    contract_addr_hex: &str,
    _keeper_addr_hex: &str,
    tx: mpsc::Sender<BlockRange>,
    reveal_delay_blocks: u64,
) {
    let _ = contract_addr_hex; // sidecar has contract hardcoded for now
    let _ = reveal_delay_blocks; // sidecar handles reveal delay

    tracing::info!(
        "Starting minedTransactions sidecar watcher (Python websockets)"
    );

    loop {
        tracing::info!("Launching Python sidecar: {}", SIDECAR_SCRIPT);

        let mut child = match Command::new("python3")
            .arg(SIDECAR_SCRIPT)
            .env("MINED_TX_WS_URL", ws_url)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                tracing::error!(
                    "Failed to spawn sidecar: {:?}. Retrying in {}s",
                    e,
                    RECONNECT_DELAY.as_secs()
                );
                tokio::time::sleep(RECONNECT_DELAY).await;
                continue;
            }
        };

        let stdout = match child.stdout.take() {
            Some(s) => s,
            None => {
                tracing::error!("Sidecar has no stdout");
                tokio::time::sleep(RECONNECT_DELAY).await;
                continue;
            }
        };
        let stderr = match child.stderr.take() {
            Some(s) => s,
            None => {
                tracing::error!("Sidecar has no stderr");
                tokio::time::sleep(RECONNECT_DELAY).await;
                continue;
            }
        };

        // Log stderr in a background task
        let mut stderr_reader = BufReader::new(stderr).lines();
        tokio::spawn(async move {
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                tracing::info!("sidecar: {}", line);
            }
        });

        let mut stdout_reader = BufReader::new(stdout).lines();
        // Initialize last_sent_block to the current chain head so we don't
        // replay the entire chain history. Fetch via eth_blockNumber.
        let mut last_sent_block: u64 = match fetch_latest_block(ws_url).await {
            Ok(b) => b,
            Err(e) => {
                tracing::warn!(
                    "sidecar: failed to fetch initial block ({}), starting from 0",
                    e
                );
                0
            }
        };
        tracing::info!(
            "sidecar: initial last_sent_block = {}",
            last_sent_block
        );

        loop {
            match stdout_reader.next_line().await {
                Ok(Some(line)) => {
                    // Parse JSON: {"block": N, "tx": "0x..."}
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) {
                        if let Some(block) = v.get("block").and_then(|b| b.as_u64()) {
                            let tx_hash = v
                                .get("tx")
                                .and_then(|t| t.as_str())
                                .unwrap_or("?");
                            let safe = block;

                            if safe > last_sent_block {
                                tracing::info!(
                                    "sidecar: requestV2 in tx {} at safe block #{}. Sending range immediately.",
                                    tx_hash,
                                    safe
                                );
                                let from = last_sent_block + 1;
                                let to = safe;
                                if let Err(e) =
                                    tx.send(BlockRange { from, to }).await
                                {
                                    tracing::error!(
                                        "sidecar: failed to send range: {}",
                                        e
                                    );
                                }
                                last_sent_block = safe;
                            } else {
                                // Already covered — resend this single block
                                tracing::info!(
                                    "sidecar: requestV2 in tx {} at block #{} (already covered). Resending.",
                                    tx_hash,
                                    safe
                                );
                                if let Err(e) = tx
                                    .send(BlockRange {
                                        from: safe,
                                        to: safe,
                                    })
                                    .await
                                {
                                    tracing::error!(
                                        "sidecar: failed to resend: {}",
                                        e
                                    );
                                }
                            }
                        }
                    }
                }
                Ok(None) => {
                    tracing::warn!(
                        "Sidecar stdout closed, restarting in {}s",
                        RECONNECT_DELAY.as_secs()
                    );
                    let _ = child.kill().await;
                    tokio::time::sleep(RECONNECT_DELAY).await;
                    break;
                }
                Err(e) => {
                    tracing::error!("Sidecar stdout read error: {:?}", e);
                    let _ = child.kill().await;
                    tokio::time::sleep(RECONNECT_DELAY).await;
                    break;
                }
            }
        }
    }
}

/// Mask the API key in a WS URL for logging.
pub fn mask_ws_url(url: &str) -> String {
    if let Some(idx) = url.rfind('/') {
        let prefix = &url[..idx + 1];
        let suffix = &url[idx + 1..];
        if suffix.len() > 8 {
            return format!("{}***{}", prefix, &suffix[suffix.len() - 4..]);
        }
    }
    url.to_string()
}

/// Fetch the latest block number via HTTP RPC (convert WSS URL to HTTPS).
/// Used to initialize last_sent_block so we don't replay chain history.
async fn fetch_latest_block(ws_url: &str) -> Result<u64, String> {
    // Convert wss:// to https:// for the HTTP endpoint
    let http_url = ws_url
        .replace("wss://", "https://")
        .replace("ws://", "http://");

    let body = r#"{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}"#;
    let client = reqwest::Client::new();
    let resp = client
        .post(&http_url)
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    let v: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| format!("JSON parse failed: {}", e))?;

    let block_hex = v
        .get("result")
        .and_then(|r| r.as_str())
        .ok_or("no result in response")?;

    u64::from_str_radix(block_hex.trim_start_matches("0x"), 16)
        .map_err(|e| format!("block parse failed: {}", e))
}
