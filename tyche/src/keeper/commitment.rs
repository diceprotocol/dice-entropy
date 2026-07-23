use {
    crate::{
        api::BlockchainState, chain::ethereum::InstrumentedSignableDiceContract,
        eth_utils::utils::send_and_confirm, keeper::block::get_latest_safe_block,
    },
    anyhow::{anyhow, Result},
    std::sync::Arc,
    tokio::time::{self, Duration},
    tracing::{self, Instrument},
};

/// Check whether we need to manually update the commitments to reduce numHashes for future
/// requests and reduce the gas cost of the reveal.
/// How often to check whether commitments need updating.
const UPDATE_COMMITMENTS_INTERVAL: Duration = Duration::from_secs(30);
const UPDATE_COMMITMENTS_THRESHOLD_FACTOR: f64 = 0.95;
/// After this many consecutive commitment advancement failures, escalate to CRITICAL.
const COMMITMENT_FAILURE_THRESHOLD: u32 = 5;

#[tracing::instrument(name = "update_commitments", skip_all)]
pub async fn update_commitments_loop(
    contract: Arc<InstrumentedSignableDiceContract>,
    chain_state: BlockchainState,
) {
    let mut consecutive_failures: u32 = 0;
    loop {
        if let Err(e) = update_commitments_if_necessary(contract.clone(), &chain_state)
            .in_current_span()
            .await
        {
            consecutive_failures += 1;
            if consecutive_failures >= COMMITMENT_FAILURE_THRESHOLD {
                tracing::error!(
                    consecutive_failures = consecutive_failures,
                    "Commitment advancement has failed {} consecutive times — numHashes is growing and may cause LastRevealedTooOld. Immediate investigation required. error: {:?}",
                    consecutive_failures,
                    e
                );
            } else {
                tracing::error!(
                    consecutive_failures = consecutive_failures,
                    "Update commitments failed (attempt {}). error: {:?}",
                    consecutive_failures,
                    e
                );
            }
        } else {
            if consecutive_failures > 0 {
                tracing::info!(
                    consecutive_failures = consecutive_failures,
                    "Commitment advancement recovered after {} failures",
                    consecutive_failures
                );
            }
            consecutive_failures = 0;
        }
        time::sleep(UPDATE_COMMITMENTS_INTERVAL).await;
    }
}

pub async fn update_commitments_if_necessary(
    contract: Arc<InstrumentedSignableDiceContract>,
    chain_state: &BlockchainState,
) -> Result<()> {
    //TODO: we can reuse the result from the last call from the watch_blocks thread to reduce RPCs
    let latest_safe_block = get_latest_safe_block(chain_state).in_current_span().await?;
    let provider_address = chain_state.provider_address;
    let provider_info = contract
        .get_provider_info_v2(provider_address)
        .block(latest_safe_block) // To ensure we are not revealing sooner than we should
        .call()
        .await
        .map_err(|e| {
            anyhow!(
                "Error while getting provider info at block {}. error: {:?}",
                latest_safe_block,
                e
            )
        })?;
    if provider_info.max_num_hashes == 0 {
        return Ok(());
    }
    let threshold =
        ((provider_info.max_num_hashes as f64) * UPDATE_COMMITMENTS_THRESHOLD_FACTOR) as u64;
    // Use saturating_sub to prevent underflow during reorgs or RPC inconsistency
    let outstanding_requests =
        provider_info.sequence_number.saturating_sub(provider_info.current_commitment_sequence_number);
    if outstanding_requests > threshold {
        // NOTE: This log message triggers a grafana alert. If you want to change the text, please change the alert also.
        tracing::warn!("Update commitments threshold reached -- possible outage or DDOS attack. Number of outstanding requests: {:?} Threshold: {:?}", outstanding_requests, threshold);
        // Guard against sequence_number == 0 (would underflow)
        let seq_number = provider_info.sequence_number.saturating_sub(1);
        if seq_number == 0 {
            return Ok(());
        }
        let provider_revelation = chain_state
            .state
            .reveal(seq_number)
            .map_err(|e| anyhow!("Error revealing: {:?}", e))?;
        let contract_call =
            contract.advance_provider_commitment(provider_address, seq_number, provider_revelation);
        send_and_confirm(contract_call).await?;
    }
    Ok(())
}
