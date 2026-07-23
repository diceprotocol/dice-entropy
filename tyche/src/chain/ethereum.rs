#![allow(clippy::same_name_method, reason = "generated code")]

use {
    crate::{
        api::ChainId,
        chain::reader::{
            self, BlockNumber, BlockStatus, EntropyReader, RequestedV2Event, RevealedV2Event,
        },
        config::EthereumConfig,
        eth_utils::{
            eth_gas_oracle::EthProviderOracle,
            legacy_tx_middleware::LegacyTxMiddleware,
            nonce_manager::NonceManagerMiddleware,
            traced_client::{RpcMetrics, TracedClient},
        },
    },
    anyhow::{anyhow, Error, Result},
    axum::async_trait,
    ethers::{
        abi::RawLog,
        contract::{abigen, EthLogDecode, LogMeta},
        core::types::Address,
        middleware::{gas_oracle::GasOracleMiddleware, SignerMiddleware},
        prelude::JsonRpcClient,
        providers::{Http, Middleware, Provider},
        signers::{LocalWallet, Signer},
        types::{BlockNumber as EthersBlockNumber, H256, U256},
    },
    sha3::{Digest, Keccak256},
    std::{sync::Arc, time::Duration},
};

// TODO: Programmatically generate this so we don't have to keep committed ABI in sync with the
// contract in the same repo.
abigen!(
    DiceRandom,
    "../contracts/target_chains/ethereum/entropy_sdk/solidity/abis/IEntropy.json";
    DiceRandomErrors,
    "../contracts/target_chains/ethereum/entropy_sdk/solidity/abis/EntropyErrors.json"
);

pub type MiddlewaresWrapper<T> = LegacyTxMiddleware<
    GasOracleMiddleware<
        NonceManagerMiddleware<SignerMiddleware<Provider<T>, LocalWallet>>,
        EthProviderOracle<Provider<T>>,
    >,
>;

pub type SignableDiceContractInner<T> = DiceRandom<MiddlewaresWrapper<T>>;
pub type SignableDiceContract = SignableDiceContractInner<Http>;
pub type InstrumentedSignableDiceContract = SignableDiceContractInner<TracedClient>;

pub type DiceContract = DiceRandom<Provider<Http>>;
pub type InstrumentedDiceContract = DiceRandom<Provider<TracedClient>>;

impl<T: JsonRpcClient + 'static + Clone> SignableDiceContractInner<T> {
    /// Get the wallet that signs transactions sent to this contract.
    pub fn wallet(&self) -> LocalWallet {
        self.client().inner().inner().inner().signer().clone()
    }

    /// Get the underlying provider that communicates with the blockchain.
    pub fn provider(&self) -> Provider<T> {
        self.client().inner().inner().inner().provider().clone()
    }

    /// Submit a request for a random number to the contract.
    ///
    /// This method is a version of the autogenned `request` method that parses the emitted logs
    /// to return the sequence number of the created Request.
    pub async fn request_wrapper(
        &self,
        provider: &Address,
        user_randomness: &[u8; 32],
        _use_blockhash: bool,
    ) -> Result<u64> {
        let fee = self.get_fee(*provider).call().await?;

        let hashed_randomness: [u8; 32] = Keccak256::digest(user_randomness).into();

        if let Some(r) = self
            .request_v_23(*provider, hashed_randomness, 0)
            .value(fee)
            .send()
            .await?
            .await?
        {
            // Extract Log from TransactionReceipt.
            let l: RawLog = r.logs[0].clone().into();
            if let DiceRandomEvents::RequestedFilter(r) = DiceRandomEvents::decode_log(&l)? {
                Ok(r.sequence_number)
            } else {
                Err(anyhow!("No log with sequence number"))
            }
        } else {
            Err(anyhow!("Request failed"))
        }
    }

    /// Submit a request for a random number to the contract.
    ///
    /// This method is a version of the autogenned `request` method that parses the emitted logs
    /// to return the sequence number of the created Request.
    pub async fn request_with_callback_wrapper(
        &self,
        provider: &Address,
        user_randomness: &[u8; 32],
    ) -> Result<u64> {
        let fee = self.get_fee(*provider).call().await?;

        if let Some(r) = self
            .request_v_23(*provider, *user_randomness, 0)
            .value(fee)
            .send()
            .await?
            .await?
        {
            // Extract Log from TransactionReceipt.
            let l: RawLog = r.logs[0].clone().into();
            if let DiceRandomEvents::RequestedFilter(r) = DiceRandomEvents::decode_log(&l)? {
                Ok(r.sequence_number)
            } else {
                Err(anyhow!("No log with sequence number"))
            }
        } else {
            Err(anyhow!("Request failed"))
        }
    }

    /// Reveal the generated random number to the contract.
    ///
    /// This method is a version of the autogenned `reveal` method that parses the emitted logs
    /// to return the generated random number.
    pub async fn reveal_wrapper(
        &self,
        provider: &Address,
        sequence_number: u64,
        user_randomness: &[u8; 32],
        provider_randomness: &[u8; 32],
    ) -> Result<[u8; 32]> {
        if let Some(r) = self
            .reveal(
                *provider,
                sequence_number,
                *user_randomness,
                *provider_randomness,
            )
            .send()
            .await?
            .await?
        {
            if let DiceRandomEvents::RevealedFilter(r) =
                DiceRandomEvents::decode_log(&r.logs[0].clone().into())?
            {
                Ok(r.random_number)
            } else {
                Err(anyhow!("No log with randomnumber"))
            }
        } else {
            Err(anyhow!("Request failed"))
        }
    }

    pub fn from_config_and_provider_and_network_id(
        chain_config: &EthereumConfig,
        private_key: &str,
        provider: Provider<T>,
        network_id: u64,
    ) -> Result<SignableDiceContractInner<T>> {
        let gas_oracle = EthProviderOracle::new(
            provider.clone(),
            chain_config.priority_fee_multiplier_pct,
            chain_config.min_reward_samples,
            chain_config.fee_estimation_past_blocks,
            chain_config.fee_estimation_reward_percentile,
            chain_config.eip1559_fee_estimation_default_priority_fee,
            chain_config.eip1559_fee_estimation_priority_fee_trigger,
            chain_config.eip1559_fee_estimation_threshold_max_change,
            chain_config.surge_threshold_1,
            chain_config.surge_threshold_2,
            chain_config.surge_threshold_3,
        );
        let wallet__ = private_key
            .parse::<LocalWallet>()?
            .with_chain_id(network_id);

        let address = wallet__.address();

        Ok(DiceRandom::new(
            chain_config.contract_addr,
            Arc::new(LegacyTxMiddleware::new(
                chain_config.legacy_tx,
                GasOracleMiddleware::new(
                    NonceManagerMiddleware::new(SignerMiddleware::new(provider, wallet__), address),
                    gas_oracle,
                ),
            )),
        ))
    }

    pub async fn from_config_and_provider(
        chain_config: &EthereumConfig,
        private_key: &str,
        provider: Provider<T>,
    ) -> Result<SignableDiceContractInner<T>> {
        let network_id = provider.get_chainid().await?.as_u64();
        Self::from_config_and_provider_and_network_id(
            chain_config,
            private_key,
            provider,
            network_id,
        )
    }
}

impl SignableDiceContract {
    pub async fn from_config(chain_config: &EthereumConfig, private_key: &str) -> Result<Self> {
        let provider = Provider::<Http>::try_from(&chain_config.geth_rpc_addr)?
            .interval(Duration::from_millis(200));
        Self::from_config_and_provider(chain_config, private_key, provider).await
    }
}

impl InstrumentedSignableDiceContract {
    pub fn from_config(
        chain_config: &EthereumConfig,
        private_key: &str,
        chain_id: ChainId,
        metrics: Arc<RpcMetrics>,
        network_id: u64,
    ) -> Result<Self> {
        let provider = TracedClient::new(chain_id, &chain_config.geth_rpc_addr, metrics)?
            .interval(Duration::from_millis(200));
        Self::from_config_and_provider_and_network_id(
            chain_config,
            private_key,
            provider,
            network_id,
        )
    }
}

impl DiceContract {
    pub fn from_config(chain_config: &EthereumConfig) -> Result<Self> {
        let provider = Provider::<Http>::try_from(&chain_config.geth_rpc_addr)?
            .interval(Duration::from_millis(200));

        Ok(DiceRandom::new(
            chain_config.contract_addr,
            Arc::new(provider),
        ))
    }
}

impl InstrumentedDiceContract {
    pub fn from_config(
        chain_config: &EthereumConfig,
        chain_id: ChainId,
        metrics: Arc<RpcMetrics>,
    ) -> Result<Self> {
        let provider = TracedClient::new(chain_id, &chain_config.geth_rpc_addr, metrics)?
            .interval(Duration::from_millis(200));

        Ok(DiceRandom::new(
            chain_config.contract_addr,
            Arc::new(provider),
        ))
    }
}

impl<T: JsonRpcClient + 'static> DiceRandom<Provider<T>> {
    pub async fn get_network_id(&self) -> Result<U256> {
        let chain_id = self.client().get_chainid().await?;
        Ok(chain_id)
    }
}

#[async_trait]
impl<T: JsonRpcClient + 'static> EntropyReader for DiceRandom<Provider<T>> {
    async fn get_request_v2(
        &self,
        provider_address: Address,
        sequence_number: u64,
    ) -> Result<Option<reader::Request>> {
        let request = self
            .get_request_v2(provider_address, sequence_number)
            .call()
            .await?;
        if request.sequence_number == 0 {
            Ok(None)
        } else {
            Ok(Some(reader::Request {
                provider: request.provider,
                sequence_number: request.sequence_number,
                block_number: request.block_number,
                use_blockhash: request.use_blockhash,
                callback_status: reader::RequestCallbackStatus::try_from(request.callback_status)?,
                gas_limit_10k: request.gas_limit_1_0k,
            }))
        }
    }

    async fn get_block_number(&self, confirmed_block_status: BlockStatus) -> Result<BlockNumber> {
        let block_number: EthersBlockNumber = confirmed_block_status.into();
        let block = self
            .client()
            .get_block(block_number)
            .await?
            .ok_or_else(|| Error::msg("pending block confirmation"))?;

        Ok(block
            .number
            .ok_or_else(|| Error::msg("pending confirmation"))?
            .as_u64())
    }

    async fn get_request_with_callback_events(
        &self,
        from_block: BlockNumber,
        to_block: BlockNumber,
        provider: Address,
    ) -> Result<Vec<RequestedV2Event>> {
        // Robinhood Chain's RPC does not reliably index event topics.
        // Querying with topic0 or topic1 filters returns empty results.
        // We query ALL logs for the contract address and decode in-memory.
        use ethers::types::{Filter, ValueOrArray, BlockNumber as EthersBlockNumber};

        let filter = Filter::new()
            .address(ValueOrArray::Value(self.address()))
            .from_block(EthersBlockNumber::Number(from_block.into()))
            .to_block(EthersBlockNumber::Number(to_block.into()));

        let logs = self.client().get_logs(&filter).await?;

        let mut events = Vec::new();
        for log in logs {
            // Decode and check if it's a Requested event
            let raw_log: RawLog = log.clone().into();
            if let Ok(DiceRandomEvents::RequestedFilter(r)) =
                DiceRandomEvents::decode_log(&raw_log)
            {
                if r.provider == provider {
                    let meta = LogMeta {
                        address: log.address,
                        block_number: log.block_number.unwrap_or_default(),
                        block_hash: log.block_hash.unwrap_or_default(),
                        transaction_hash: log.transaction_hash.unwrap_or_default(),
                        transaction_index: log.transaction_index.unwrap_or_default(),
                        log_index: log.log_index.unwrap_or_default(),
                    };
                    events.push(RequestedV2Event {
                        sequence_number: r.sequence_number,
                        user_random_number: r.user_contribution,
                        provider_address: r.provider,
                        sender: r.caller,
                        gas_limit: r.gas_limit,
                        log_meta: meta,
                    });
                }
            }
        }
        Ok(events)
    }

    async fn get_revealed_event(
        &self,
        provider: Address,
        sequence_number: u64,
        from_block: BlockNumber,
    ) -> Result<Option<RevealedV2Event>> {
        let mut event = self.revealed_filter();
        // provider and sequence_number are indexed (topic1, topic3), so filter server-side to this
        // single request rather than scanning the whole block range.
        event.filter = event
            .filter
            .address(self.address())
            .from_block(from_block)
            .topic1(provider)
            .topic3(H256::from_low_u64_be(sequence_number));

        let res: Vec<(RevealedFilter, LogMeta)> = event.query_with_meta().await?;
        // The callback-failed branch emits a Revealed event without clearing the request, so only a
        // `callback_failed == false` event is a clearing reveal.
        let Some((revealed, log_meta)) = res.into_iter().find(|(r, _)| !r.callback_failed) else {
            return Ok(None);
        };

        let gas_used = self
            .client()
            .get_transaction_receipt(log_meta.transaction_hash)
            .await
            .ok()
            .flatten()
            .and_then(|receipt| receipt.gas_used)
            .unwrap_or_default();

        Ok(Some(RevealedV2Event {
            provider_revelation: revealed.provider_contribution,
            random_number: revealed.random_number,
            callback_failed: revealed.callback_failed,
            callback_return_value: revealed.callback_return_value,
            callback_gas_used: revealed.callback_gas_used,
            gas_used,
            log_meta,
        }))
    }

    async fn estimate_reveal_with_callback_gas(
        &self,
        sender: Address,
        provider: Address,
        sequence_number: u64,
        user_random_number: [u8; 32],
        provider_revelation: [u8; 32],
    ) -> Result<U256> {
        let result = self
            .reveal_with_callback(
                provider,
                sequence_number,
                user_random_number,
                provider_revelation,
            )
            .from(sender)
            .estimate_gas()
            .await;

        result.map_err(|e| e.into())
    }
}
