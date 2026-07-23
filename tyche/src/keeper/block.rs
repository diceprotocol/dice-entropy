use {
    crate::{
        api::BlockchainState,
        chain::{ethereum::InstrumentedSignableDiceContract, reader::BlockNumber},
        config::ReplicaConfig,
        eth_utils::utils::EscalationPolicy,
        history::History,
        keeper::{
            keeper_metrics::{ChainIdLabel, KeeperMetrics},
            process_event::process_event_with_backoff,
        },
    },
    anyhow::Result,
    std::time::{SystemTime, UNIX_EPOCH},
    std::{collections::HashSet, sync::Arc},
    tokio::{
        spawn,
        sync::{mpsc, RwLock},
        time::{self, Duration},
    },
    tracing::{self, Instrument},
};

/// How much to wait before retrying in case of an RPC error
const RETRY_INTERVAL: Duration = Duration::from_secs(5);
/// Throttle between successive block-batch RPC calls to avoid hammering the
/// public RPC endpoint (which enforces HTTP 429 rate limits). Only relevant
/// when a range spans multiple batches (backlog catch-up).
const BATCH_THROTTLE: Duration = Duration::from_millis(150);
/// Maximum number of retries before giving up on a block batch.
/// After this many consecutive RPC failures, the batch is skipped.
/// The next block range scan (from process_new_blocks) will reprocess it.
const MAX_RPC_RETRIES: u32 = 10;
/// Number of recent sequence numbers to retain in the fulfilled_requests_cache.
/// Entries older than this are pruned to prevent unbounded memory growth.
const CACHE_RETENTION_WINDOW: u64 = 10_000;
/// How many blocks to fetch events for in a single rpc call
const BLOCK_BATCH_SIZE: u64 = 100; // Alchemy free tier: max 10 blocks INCLUSIVE (to-from+1 <= 10)
/// How much to wait before polling the next latest block.
/// Only used when WS is NOT configured (HTTP polling mode).

/// Check if an error string indicates a rate-limit (HTTP 429) or timeout.
/// Used to trigger fallback RPC retry.
fn is_rate_limit_error(err: &str) -> bool {
    err.contains("429")
        || err.contains("Too Many Requests")
        || err.contains("rate.?limit")
        || err.contains("i/o timeout")
        || err.contains("connection refused")
}
/// Polling interval for HTTP mode. 1s gives ~0.5s average detection overhead
/// after a tx is mined, at ~190ms per eth_blockNumber call on public RPC.
const POLL_INTERVAL: Duration = Duration::from_secs(1);
/// Retry last N blocks. This overlap guards against missing events if the RPC
/// briefly returned a stale head. On Robinhood Chain (~0.1s blocks) the head
/// advances ~10-15 blocks per 1s poll cycle, so a 20-block overlap fully covers
/// normal jitter without re-scanning ~10s of history every cycle (which was the
/// dominant source of public-RPC 429 rate-limiting).
const RETRY_PREVIOUS_BLOCKS: u64 = 20;

#[derive(Debug, Clone)]
pub struct BlockRange {
    pub from: BlockNumber,
    pub to: BlockNumber,
}

#[derive(Clone)]
pub struct ProcessParams {
    pub contract: Arc<InstrumentedSignableDiceContract>,
    pub escalation_policy: EscalationPolicy,
    pub chain_state: BlockchainState,
    pub replica_config: Option<ReplicaConfig>,
    pub metrics: Arc<KeeperMetrics>,
    pub history: Arc<History>,
    pub fulfilled_requests_cache: Arc<RwLock<HashSet<u64>>>,
    /// Serializes reveal submissions to prevent nonce collisions.
    pub reveal_lock: Arc<tokio::sync::Mutex<()>>,
}

/// Get the latest safe block number for the chain. Bounded retry — returns
/// `Err` after `MAX_SAFE_BLOCK_RETRIES` consecutive failures so the caller
/// can decide whether to escalate, skip, or let systemd restart the keeper.
pub async fn get_latest_safe_block(chain_state: &BlockchainState) -> Result<BlockNumber> {
    const MAX_SAFE_BLOCK_RETRIES: u32 = 20;
    let mut retries = 0u32;
    loop {
        match chain_state
            .contract
            .get_block_number(chain_state.confirmed_block_status)
            .await
        {
            Ok(latest_confirmed_block) => {
                let safe = latest_confirmed_block - chain_state.reveal_delay_blocks;
                tracing::info!("Fetched latest safe block {}", safe);
                return Ok(safe);
            }
            Err(e) => {
                retries += 1;
                if retries >= MAX_SAFE_BLOCK_RETRIES {
                    tracing::error!(
                        retries,
                        "Failed to fetch latest safe block after {} attempts. Giving up. Last error: {:?}",
                        retries,
                        e
                    );
                    return Err(anyhow::anyhow!(
                        "Failed to fetch latest safe block after {} retries: {:?}",
                        retries,
                        e
                    ));
                }
                tracing::error!(
                    "Error while getting block number (attempt {}/{}). error: {:?}",
                    retries,
                    MAX_SAFE_BLOCK_RETRIES,
                    e
                );
                time::sleep(RETRY_INTERVAL).await;
            }
        }
    }
}

/// Process a range of blocks in batches. It calls the `process_single_block_batch` method for each batch.
#[tracing::instrument(skip_all, fields(
    range_from_block = block_range.from, range_to_block = block_range.to
))]
pub async fn process_block_range(block_range: BlockRange, process_params: ProcessParams) {
    let BlockRange {
        from: first_block,
        to: last_block,
    } = block_range;
    let mut current_block = first_block;
    while current_block <= last_block {
        let mut to_block = current_block + BLOCK_BATCH_SIZE;
        if to_block > last_block {
            to_block = last_block;
        }

        // TODO: this is handling all blocks sequentially we might want to handle them in parallel in future.
        process_single_block_batch(
            BlockRange {
                from: current_block,
                to: to_block,
            },
            process_params.clone(),
        )
        .in_current_span()
        .await;

        current_block = to_block + 1;

        // Throttle between batches to avoid hammering the public RPC endpoint.
        // Normal operation processes 1-3 blocks per cycle (no throttle needed).
        // Only fires during backlog catch-up when a range spans multiple batches.
        if current_block <= last_block {
            time::sleep(BATCH_THROTTLE).await;
        }
    }
}

/// Process a batch of blocks for a chain. It will fetch events for all the blocks in a single call for the provided batch
/// and then try to process them one by one. It checks the `fulfilled_request_cache`. If the request was already fulfilled.
/// It won't reprocess it. If the request was already processed, it will reprocess it.
/// If the process fails, it will retry up to MAX_RPC_RETRIES times, then skip the batch.
#[tracing::instrument(name = "batch", skip_all, fields(
    batch_from_block = block_range.from, batch_to_block = block_range.to
))]

pub async fn process_single_block_batch(block_range: BlockRange, process_params: ProcessParams) {
    let label = ChainIdLabel {
        chain_id: process_params.chain_state.id.clone(),
    };
    let mut retry_count: u32 = 0;
    loop {
        let events_res = process_params
            .chain_state
            .contract
            .get_request_with_callback_events(
                block_range.from,
                block_range.to,
                process_params.chain_state.provider_address,
            )
            .await;

        // If primary RPC failed AND we have a fallback contract, retry with it.
        let events_res = match events_res {
            Err(ref e) if is_rate_limit_error(&e.to_string()) => {
                if let Some(ref fallback) = process_params.chain_state.fallback_contract {
                    tracing::warn!(
                        "Primary RPC rate-limited, retrying batch [{}, {}] against fallback RPC",
                        block_range.from,
                        block_range.to
                    );
                    fallback
                        .get_request_with_callback_events(
                            block_range.from,
                            block_range.to,
                            process_params.chain_state.provider_address,
                        )
                        .await
                } else {
                    events_res
                }
            }
            other => other,
        };

        // Only update metrics if we successfully retrieved events.
        if events_res.is_ok() {
            // Track the last time blocks were processed. If anything happens to the processing thread, the
            // timestamp will lag, which will trigger an alert.
            let server_timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_secs() as i64)
                .unwrap_or(0);
            process_params
                .metrics
                .process_event_timestamp
                .get_or_create(&label)
                .set(server_timestamp);

            let current_block = process_params
                .metrics
                .process_event_block_number
                .get_or_create(&label)
                .get();
            if block_range.to > current_block as u64 {
                process_params
                    .metrics
                    .process_event_block_number
                    .get_or_create(&label)
                    .set(block_range.to as i64);
            }
        }

        match events_res {
            Ok(events) => {
                tracing::info!(num_of_events = &events.len(), "Processing",);

                // Prune fulfilled_requests_cache to prevent unbounded memory growth.
                // Keep only entries from the last CACHE_RETENTION_WINDOW sequence numbers.
                if let Some(max_seq) = events.iter().map(|e| e.sequence_number).max() {
                    let retention_floor = max_seq.saturating_sub(CACHE_RETENTION_WINDOW);
                    let mut cache = process_params.fulfilled_requests_cache.write().await;
                    let before = cache.len();
                    cache.retain(|&seq| seq >= retention_floor);
                    let pruned = before.saturating_sub(cache.len());
                    if pruned > 0 {
                        tracing::debug!(
                            pruned,
                            remaining = cache.len(),
                            retention_floor,
                            "Pruned fulfilled_requests_cache"
                        );
                    }
                }

                for event in &events {
                    // the write lock guarantees we spawn only one task per sequence number
                    let newly_inserted = process_params
                        .fulfilled_requests_cache
                        .write()
                        .await
                        .insert(event.sequence_number);
                    if newly_inserted {
                        spawn(
                            process_event_with_backoff(event.clone(), process_params.clone())
                                .in_current_span(),
                        );
                    }
                }
                tracing::info!(num_of_events = &events.len(), "Processed",);
                break;
            }
            Err(e) => {
                retry_count += 1;
                if retry_count >= MAX_RPC_RETRIES {
                    tracing::error!(
                        from_block = block_range.from,
                        to_block = block_range.to,
                        retries = retry_count,
                        "RPC failed {} times for block batch [{}, {}]. Skipping — will be reprocessed by next block range scan. error: {:?}",
                        retry_count,
                        block_range.from,
                        block_range.to,
                        e
                    );
                    break;
                }
                tracing::error!(
                    "Error while getting events (attempt {}/{}). Waiting {}s before retry. error: {:?}",
                    retry_count,
                    MAX_RPC_RETRIES,
                    RETRY_INTERVAL.as_secs(),
                    e
                );
                time::sleep(RETRY_INTERVAL).await;
            }
        }
    }
}

/// Wrapper for the `watch_blocks` method. If there was an error while watching, it will retry after a delay.
/// It retries indefinitely. Only used when WS is NOT configured.
#[tracing::instrument(name = "watch_blocks", skip_all, fields(
    initial_safe_block = latest_safe_block
))]
pub async fn watch_blocks_wrapper(
    chain_state: BlockchainState,
    latest_safe_block: BlockNumber,
    tx: mpsc::Sender<BlockRange>,
) {
    tracing::info!("HTTP polling mode, interval: {}s", POLL_INTERVAL.as_secs());
    let mut last_safe_block_processed = latest_safe_block;
    loop {
        if let Err(e) = watch_blocks(
            chain_state.clone(),
            &mut last_safe_block_processed,
            tx.clone(),
            POLL_INTERVAL,
        )
        .in_current_span()
        .await
        {
            tracing::error!("watching blocks. error: {:?}", e);
            time::sleep(RETRY_INTERVAL).await;
        }
    }
}

/// Watch for new blocks and send the range of blocks for which events have not been handled to the `tx` channel.
/// We are subscribing to new blocks instead of events. If we miss some blocks, it will be fine as we are sending
/// block ranges to the `tx` channel. If we have subscribed to events, we could have missed those and won't even
/// know about it.
pub async fn watch_blocks(
    chain_state: BlockchainState,
    last_safe_block_processed: &mut BlockNumber,
    tx: mpsc::Sender<BlockRange>,
    poll_interval: Duration,
) -> Result<()> {
    tracing::info!("Watching blocks to handle new events");

    loop {
        time::sleep(poll_interval).await;

        let latest_safe_block = match get_latest_safe_block(&chain_state).in_current_span().await {
            Ok(block) => block,
            Err(e) => {
                tracing::error!("watch_blocks: failed to get latest safe block: {}. Will retry next cycle.", e);
                continue;
            }
        };
        if latest_safe_block > *last_safe_block_processed {
            let mut from = latest_safe_block.saturating_sub(RETRY_PREVIOUS_BLOCKS);

            // In normal situation, the difference between latest and last safe block should not be more than 2-3 (for arbitrum it can be 10)
            // TODO: add a metric for this in separate PR. We need alerts
            // But in extreme situation, where we were unable to send the block range multiple times, the difference between latest_safe_block and
            // last_safe_block_processed can grow. It is fine to not have the retry mechanisms for those earliest blocks as we expect the rpc
            // to be in consistency after this much time.
            if from > *last_safe_block_processed {
                from = *last_safe_block_processed;
            }
            match tx
                .send(BlockRange {
                    from,
                    to: latest_safe_block,
                })
                .await
            {
                Ok(_) => {
                    tracing::info!(
                        from_block = from,
                        to_block = &latest_safe_block,
                        "Block range sent to handle events",
                    );
                    *last_safe_block_processed = latest_safe_block;
                }
                Err(e) => {
                    tracing::error!(
                        from_block = from,
                        to_block = &latest_safe_block,
                        "Error while sending block range to handle events. These will be handled in next call. error: {:?}",
                        e
                    );
                }
            };
        }
    }
}

/// It waits on rx channel to receive block ranges and then calls process_block_range to process them
/// for each configured block delay.
#[tracing::instrument(skip_all)]
pub async fn process_new_blocks(
    process_params: ProcessParams,
    mut rx: mpsc::Receiver<BlockRange>,
    block_delays: Vec<u64>,
) {
    tracing::info!("Waiting for new block ranges to process");
    loop {
        if let Some(block_range) = rx.recv().await {
            // Process blocks immediately first
            process_block_range(block_range.clone(), process_params.clone())
                .in_current_span()
                .await;

            // Then process with each configured delay
            for delay in &block_delays {
                let adjusted_range = BlockRange {
                    from: block_range.from.saturating_sub(*delay),
                    to: block_range.to.saturating_sub(*delay),
                };
                process_block_range(adjusted_range, process_params.clone())
                    .in_current_span()
                    .await;
            }
        }
    }
}

/// Processes the backlog_range for a chain.
/// On restart, scans recent blocks to catch any events missed while down.
#[tracing::instrument(skip_all)]
pub async fn process_backlog(
    process_params: ProcessParams,
    backlog_range: BlockRange,
    block_delays: Vec<u64>,
) {
    tracing::info!("Processing backlog");
    // Process blocks immediately first
    process_block_range(backlog_range.clone(), process_params.clone())
        .in_current_span()
        .await;

    // Then process with each configured delay
    for delay in &block_delays {
        let adjusted_range = BlockRange {
            from: backlog_range.from.saturating_sub(*delay),
            to: backlog_range.to.saturating_sub(*delay),
        };
        process_block_range(adjusted_range, process_params.clone())
            .in_current_span()
            .await;
    }
    tracing::info!("Backlog processed");
}
