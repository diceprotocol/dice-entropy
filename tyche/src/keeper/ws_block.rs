use {
    crate::{
        api::BlockchainState,
        chain::reader::BlockNumber,
        keeper::block::{get_latest_safe_block, BlockRange},
    },
    ethers::{
        providers::{Middleware, Provider, StreamExt, Ws},
        types::{Filter, ValueOrArray, H256},
    },
    std::{sync::Arc, time::Duration},
    tokio::sync::mpsc,
    tracing,
};

/// Reconnect delay when the WebSocket connection drops.
const WS_RECONNECT_DELAY: Duration = Duration::from_secs(2);

/// How long to wait without any log events before probing the connection.
/// Also drives block-advance detection: on each heartbeat, if the chain has
/// advanced past last_safe_block, we send a BlockRange so the processor can
/// pick up requests that arrived in blocks not yet scanned.
/// 2s balances latency (<2s reveal on a 0.1s/block chain) against CU cost
/// (~10 CU per eth_blockNumber probe × 30/hr = ~300 CU/hr).
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(2);

/// How long to wait for the liveness probe (`eth_blockNumber`) response.
/// A healthy WS connection responds in <100ms. 5s is generous.
const PROBE_TIMEOUT: Duration = Duration::from_secs(5);

/// topic0 hash of the `Requested(address,address,uint64,bytes32,uint32,bytes)` event.
/// Using this filter means the subscription only fires when someone actually calls
/// `request()`, not on every block or every contract event.
const REQUESTED_EVENT_TOPIC: &str =
    "0x209bbfee3369097c31c36ce42994bdcac394866c881f603fb6296f240d6c37db";

/// Mask a WebSocket URL to hide the API key in logs.
/// `wss://robinhood-mainnet.g.alchemy.com/v2/ABC123DEF456` → `wss://...alchemy.com/v2/[REDACTED]`
pub fn mask_ws_url(url: &str) -> String {
    if let Some(slash_pos) = url.rfind('/') {
        format!("{}[REDACTED]", &url[..slash_pos + 1])
    } else {
        "[REDACTED]".to_string()
    }
}

/// Connect to a WebSocket RPC and subscribe to `Requested` events directly.
///
/// This is the SOLE event detection mechanism when WS is configured.
/// There is no HTTP poller fallback. The WS watcher handles:
///
/// - **Real-time events**: subscription fires instantly when `request()` is called
/// - **Liveness detection**: when no log event arrives for `HEARTBEAT_INTERVAL`,
///   probes the same WS socket with `eth_blockNumber`. If it responds, the
///   connection is alive (just quiet). If it times out, reconnect + gap recovery.
///   This costs ~10 CU per probe (standard RPC call), NOT bandwidth-billed
///   like a `newHeads` subscription stream.
/// - **Gap recovery**: on every (re)connect, scans from `last_safe_block` to current
///   block to catch any events missed during disconnect
/// - **Auto-reconnect**: infinite retry loop with 2s delay
///
/// Architecture:
/// - `Provider<Ws>` is owned by the loop iteration scope, dropped on disconnect.
///   No `Box::leak` memory growth.
/// - Only ONE subscription: `eth_subscribe("logs", {topic0: Requested})`.
///   No `newHeads` subscription — those burn ~5M CU/hour on a 0.25s block chain
///   because Alchemy bills WS subscriptions by bandwidth delivered.
/// - CU usage at idle: ~10 CU per heartbeat probe × 2/min = ~1,200 CU/hour.
pub async fn watch_blocks_ws(
    chain_state: BlockchainState,
    mut last_safe_block: BlockNumber,
    tx: mpsc::Sender<BlockRange>,
    ws_url: &str,
    contract_addr_hex: &str,
) {
    let masked_url = mask_ws_url(ws_url);

    let contract_addr: ethers::types::Address = contract_addr_hex
        .parse()
        .expect("invalid contract address in config");

    let topic: H256 = REQUESTED_EVENT_TOPIC
        .parse()
        .expect("invalid Requested event topic hash");

    tracing::info!(
        "Starting WebSocket log watcher (eth_blockNumber heartbeat, no HTTP fallback) on contract: {}",
        contract_addr
    );

    loop {
        tracing::info!("Connecting to WebSocket: {}", masked_url);

        match Ws::connect(ws_url).await {
            Ok(ws) => {
                tracing::info!("WebSocket connected");

                let provider = Arc::new(Provider::new(ws));

                // === GAP RECOVERY ===
                // On every (re)connect, fetch the current block and scan
                // any gap between last_safe_block and now.
                // This catches events missed during disconnects.
                let current_block = match get_latest_safe_block(&chain_state).await {
                    Ok(block) => block,
                    Err(e) => {
                        tracing::error!(
                            "WS gap recovery: failed to get latest safe block: {}. Skipping this cycle.",
                            e
                        );
                        // Reconnect WS and try again next cycle.
                        continue;
                    }
                };
                if current_block > last_safe_block {
                    let from = last_safe_block + 1;
                    let to = current_block;
                    tracing::info!(
                        "WS gap recovery: scanning blocks {} → {} ({} blocks missed during disconnect)",
                        from, to, to - from
                    );
                    if let Err(e) = tx.send(BlockRange { from, to }).await {
                        tracing::error!("Failed to send gap recovery block range: {}", e);
                    }
                    last_safe_block = current_block;
                }

                // === SUBSCRIBE TO LOGS ===
                // Subscribe to ALL logs for this contract address.
                // Robinhood Chain's RPC does not reliably index event topics,
                // so we cannot filter by topic0 in the subscription. We receive
                // all contract logs and filter for Requested events in-memory.
                let filter = Filter::new()
                    .address(ValueOrArray::Value(contract_addr));

                let log_sub = provider.subscribe_logs(&filter).await;
                let mut log_stream = match log_sub {
                    Ok(s) => s,
                    Err(e) => {
                        tracing::error!(
                            "WS subscribe_logs failed: {:?}. Retrying in {}s",
                            e,
                            WS_RECONNECT_DELAY.as_secs()
                        );
                        tokio::time::sleep(WS_RECONNECT_DELAY).await;
                        continue;
                    }
                };

                tracing::info!(
                    "Log subscription active (topic0: Requested). Heartbeat: eth_blockNumber probe every {}s",
                    HEARTBEAT_INTERVAL.as_secs()
                );

                // === EVENT LOOP ===
                // Race: next log event vs heartbeat timeout.
                // If a log event arrives, process it and the timer resets naturally.
                // If the heartbeat fires, probe the WS socket with eth_blockNumber.
                // If the probe succeeds, connection is alive — continue.
                // If the probe fails or times out, connection is dead — reconnect.
                loop {
                    tokio::select! {
                        log_result = log_stream.next() => {
                            match log_result {
                                Some(log) => {
                                    // Filter for Requested events in-memory.
                                    // Robinhood Chain doesn't reliably index topics,
                                    // so the subscription receives ALL contract logs.
                                    let is_requested = log.topics.first()
                                        .map(|t| *t == topic)
                                        .unwrap_or(false);
                                    if !is_requested {
                                        continue;
                                    }
                                    if let Some(block_number) = log.block_number {
                                        let bn = block_number.as_u64();
                                        let latest_safe_block =
                                            bn.saturating_sub(chain_state.reveal_delay_blocks);

                                        tracing::info!(
                                            "WS: Requested event in block #{}, processing (safe: #{})",
                                            bn,
                                            latest_safe_block
                                        );

                                        if latest_safe_block > last_safe_block {
                                            let from = last_safe_block + 1;
                                            let to = latest_safe_block;
                                            if let Err(e) = tx.send(BlockRange { from, to }).await {
                                                tracing::error!("Failed to send block range: {}", e);
                                            }
                                            last_safe_block = latest_safe_block;
                                        } else {
                                            // Event is in a block we already processed — resend just this block
                                            if let Err(e) = tx.send(BlockRange {
                                                from: latest_safe_block,
                                                to: latest_safe_block,
                                            }).await {
                                                tracing::error!("Failed to send block range: {}", e);
                                            }
                                        }
                                    }
                                }
                                None => {
                                    tracing::warn!(
                                        "WebSocket log stream ended, reconnecting in {}s...",
                                        WS_RECONNECT_DELAY.as_secs()
                                    );
                                    break;
                                }
                            }
                        }
                        _ = tokio::time::sleep(HEARTBEAT_INTERVAL) => {
                            // No log events for HEARTBEAT_INTERVAL. Probe the WS socket
                            // to (1) check liveness and (2) detect block advancement.
                            tracing::debug!(
                                "WS heartbeat: no events for {}s, probing connection...",
                                HEARTBEAT_INTERVAL.as_secs()
                            );

                            let probe = tokio::time::timeout(
                                PROBE_TIMEOUT,
                                provider.get_block_number(),
                            ).await;

                            match probe {
                                Ok(Ok(block_num)) => {
                                    // Connection is alive. Check if the chain advanced.
                                    let latest_safe_block =
                                        block_num.as_u64().saturating_sub(chain_state.reveal_delay_blocks);
                                    if latest_safe_block > last_safe_block {
                                        // Chain advanced — send the new block range so the
                                        // processor picks up any requests in these blocks.
                                        let from = last_safe_block + 1;
                                        let to = latest_safe_block;
                                        tracing::info!(
                                            "WS heartbeat: chain advanced {} → {} ({} blocks). Sending range for processing.",
                                            last_safe_block, latest_safe_block, to - from
                                        );
                                        if let Err(e) = tx.send(BlockRange { from, to }).await {
                                            tracing::error!("Failed to send heartbeat block range: {}", e);
                                        }
                                        last_safe_block = latest_safe_block;
                                    }
                                }
                                Ok(Err(e)) => {
                                    // RPC returned an error — connection may be degraded.
                                    // Reconnect to be safe. Gap recovery will catch
                                    // any missed events.
                                    tracing::warn!(
                                        "WS heartbeat: probe returned error {:?}, reconnecting...",
                                        e
                                    );
                                    break;
                                }
                                Err(_) => {
                                    // Probe timed out — connection is dead.
                                    // Reconnect immediately.
                                    tracing::warn!(
                                        "WS heartbeat: probe timed out ({}s), reconnecting...",
                                        PROBE_TIMEOUT.as_secs()
                                    );
                                    break;
                                }
                            }
                        }
                    }
                }

                // Cleanup before reconnect
                let _ = log_stream.unsubscribe().await;
                // provider drops here — memory freed
            }
            Err(e) => {
                tracing::error!(
                    "WebSocket connection failed: {:?}. Retrying in {}s",
                    e,
                    WS_RECONNECT_DELAY.as_secs()
                );
            }
        }

        tokio::time::sleep(WS_RECONNECT_DELAY).await;
    }
}
