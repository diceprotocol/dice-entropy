/**
 * Dice Protocol SDK
 * Agent-friendly RNG infrastructure for Robinhood Chain.
 *
 * Agent-friendly: immutable contract, deterministic fees, automatic reveals.
 * See SKILL.md in the repo root for full agent integration guide.
 *
 * Usage:
 *   import { DiceProtocol } from '@diceprotocol/sdk';
 *
 *   const dice = new DiceProtocol({
 *     rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
 *     contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
 *   });
 *
 *   // Request randomness
 *   const seq = await dice.requestRandom(signer, providerAddress, userRandom, gasLimit);
 *
 *   // Listen for reveals
 *   dice.onReveal((event) => {
 *     console.log('Random number:', event.randomNumber);
 *   });
 */

import { ethers, Contract, JsonRpcProvider, Wallet, EventLog, Interface } from 'ethers';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const abi = require('./abi.json') as any[];

export interface DiceProtocolConfig {
  rpcUrl: string;
  contractAddress: string;
  chainId?: number;
}

export interface ProviderInfo {
  feeInWei: bigint;
  accruedFeesInWei: bigint;
  originalCommitment: string;
  originalCommitmentSequenceNumber: bigint;
  commitmentMetadata: string;
  uri: string;
  endSequenceNumber: bigint;
  sequenceNumber: bigint;
  currentCommitment: string;
  currentCommitmentSequenceNumber: bigint;
  feeManager: string;
  maxNumHashes: number;
  defaultGasLimit: number;
}

export interface RequestInfo {
  provider: string;
  sequenceNumber: bigint;
  numHashes: number;
  commitment: string;
  blockNumber: bigint;
  requester: string;
  useBlockhash: boolean;
  callbackStatus: number;
  gasLimit10k: number;
  feePaid: bigint;
}

export interface RevealEvent {
  provider: string;
  caller: string;
  sequenceNumber: bigint;
  randomNumber: string;
  userContribution: string;
  providerContribution: string;
  callbackFailed: boolean;
  callbackReturnValue: string;
  callbackGasUsed: bigint;
}

export interface RequestEvent {
  provider: string;
  caller: string;
  sequenceNumber: bigint;
  userContribution: string;
  gasLimit: bigint;
}

export class DiceProtocol {
  private provider: JsonRpcProvider;
  private contract: Contract;
  private iface: Interface;

  constructor(config: DiceProtocolConfig) {
    this.provider = new JsonRpcProvider(config.rpcUrl);
    this.contract = new Contract(config.contractAddress, abi, this.provider);
    this.iface = new Interface(abi);
  }

  /**
   * Get the contract address
   */
  getAddress(): string {
    return this.contract.target as string;
  }

  /**
   * Get the default provider address
   */
  async getDefaultProvider(): Promise<string> {
    return await this.contract.getDefaultProvider();
  }

  /**
   * Get the fee for a request
   * @param provider The provider address (optional, uses default)
   * @param gasLimit The gas limit for the callback (optional)
   */
  async getFee(provider?: string, gasLimit?: number): Promise<bigint> {
    const p = provider || (await this.getDefaultProvider());
    if (gasLimit !== undefined) {
      return await this.contract.getFeeV2(p, gasLimit);
    }
    return await this.contract.getFee(p);
  }

  /**
   * Get provider information
   */
  async getProviderInfo(provider: string): Promise<ProviderInfo> {
    const info = await this.contract.getProviderInfoV2(provider);
    return {
      feeInWei: info[0],
      accruedFeesInWei: info[1],
      originalCommitment: info[2],
      originalCommitmentSequenceNumber: info[3],
      commitmentMetadata: info[4],
      uri: info[5],
      endSequenceNumber: info[6],
      sequenceNumber: info[7],
      currentCommitment: info[8],
      currentCommitmentSequenceNumber: info[9],
      feeManager: info[10],
      maxNumHashes: Number(info[11]),
      defaultGasLimit: Number(info[12]),
    };
  }

  /**
   * Get a request by provider and sequence number
   */
  async getRequest(provider: string, sequenceNumber: bigint): Promise<RequestInfo> {
    const req = await this.contract.getRequestV2(provider, sequenceNumber);
    return {
      provider: req[0],
      sequenceNumber: req[1],
      numHashes: Number(req[2]),
      commitment: req[3],
      blockNumber: req[4],
      requester: req[5],
      useBlockhash: req[6],
      callbackStatus: Number(req[7]),
      gasLimit10k: Number(req[8]),
      feePaid: req[9],
    };
  }

  /**
   * Get the refund delay in blocks.
   */
  async getRefundDelayBlocks(): Promise<bigint> {
    return await this.contract.getRefundDelayBlocks();
  }

  /**
   * Get accrued protocol fees
   */
  async getAccruedTreasuryFees(): Promise<bigint> {
    return await this.contract.getAccruedFees();
  }

  /**
   * Get the current protocol fee per request
   */
  async getProtocolFee(): Promise<bigint> {
    return await this.contract.getProtocolFee();
  }

  /**
   * Get total accrued protocol fees
   */
  async getAccruedFees(): Promise<bigint> {
    return await this.contract.getAccruedFees();
  }

  // ============================================================
  //                    WRITE OPERATIONS
  // ============================================================

  /**
   * Request a random number from a provider.
   * @param provider The provider address (optional, uses default)
   * @param userRandomNumber 32-byte random number (generate with crypto.getRandomValues)
   * @param gasLimit Gas limit for the callback (optional, 0 = provider default)
   * @param signer A Wallet or signer to submit the transaction
   * @returns The assigned sequence number
   */
  async requestRandom(
    signer: Wallet,
    provider: string | undefined,
    userRandomNumber: string,
    gasLimit: number = 0,
  ): Promise<bigint> {
    const connectedContract = new Contract(
      this.contract.target as string,
      abi,
      signer,
    );
    const p = provider || (await this.getDefaultProvider());
    const fee = await this.getFee(p, gasLimit);
    const tx = await connectedContract.requestV2(p, userRandomNumber, gasLimit, { value: fee });
    const receipt = await tx.wait();
    // Parse the Requested event to get the sequence number
    const logs = receipt.logs.map((log: any) => {
      try { return this.iface.parseLog(log); } catch { return null; }
    }).filter((e: any) => e && e.name === 'Requested');
    if (logs.length === 0) throw new Error('No Requested event in receipt');
    return (logs[0] as any).args.sequenceNumber;
  }

  /**
   * Reveal the provider's random number (called by the provider/keeper).
   * @param signer The provider's wallet
   * @param sequenceNumber The request sequence number
   * @param userRandomNumber The user's random number (from the request)
   * @param providerRevelation The provider's hash chain value for this sequence
   */
  async revealWithCallback(
    signer: Wallet,
    sequenceNumber: bigint,
    userRandomNumber: string,
    providerRevelation: string,
  ): Promise<string> {
    const connectedContract = new Contract(
      this.contract.target as string,
      abi,
      signer,
    );
    const provider = await signer.getAddress();
    const tx = await connectedContract.revealWithCallback(
      provider,
      sequenceNumber,
      userRandomNumber,
      providerRevelation,
    );
    const receipt = await tx.wait();
    return receipt.hash;
  }

  /**
   * Admin-only: register a provider at a specific address via registerFor.
   * @param signer Admin wallet
   * @param providerAddress Provider address to register
   * @param commitment The hash chain commitment (x_0)
   * @param chainLength Number of values in the hash chain
   * @param uri Optional URI for revelation retrieval
   * @param feeInWei Unused in single-fee model; retained for ABI compatibility
   */
  async registerProviderFor(
    signer: Wallet,
    providerAddress: string,
    commitment: string,
    chainLength: number,
    uri: string = '',
    feeInWei: bigint = 0n,
  ): Promise<string> {
    const connectedContract = new Contract(
      this.contract.target as string,
      abi,
      signer,
    );
    const tx = await connectedContract.registerFor(
      providerAddress,
      feeInWei,
      commitment,
      '0x',
      chainLength,
      uri,
    );
    const receipt = await tx.wait();
    return receipt.hash;
  }

  /**
   * Admin-only: withdraw accrued protocol fees to the vault.
   * @param signer Admin wallet
   * @param amount Amount to withdraw in wei
   */
  async withdrawFees(signer: Wallet, amount: bigint): Promise<string> {
    const connectedContract = new Contract(
      this.contract.target as string,
      abi,
      signer,
    );
    const tx = await connectedContract.withdrawFees(amount);
    const receipt = await tx.wait();
    return receipt.hash;
  }

  /**
   * Refund a stuck active request after the refund timeout.
   * Only the original requester can call this.
   */
  async refundRequest(
    signer: Wallet,
    provider: string,
    sequenceNumber: bigint,
  ): Promise<string> {
    const connectedContract = new Contract(
      this.contract.target as string,
      abi,
      signer,
    );
    const tx = await connectedContract.refundRequest(provider, sequenceNumber);
    const receipt = await tx.wait();
    return receipt.hash;
  }

  // ============================================================
  //                    EVENT LISTENERS
  // ============================================================

  /**
   * Listen for new randomness requests.
   */
  onRequest(callback: (event: RequestEvent) => void): void {
    this.contract.on('Requested', (provider, caller, sequenceNumber, userContribution, gasLimit) => {
      callback({
        provider,
        caller,
        sequenceNumber,
        userContribution,
        gasLimit,
      });
    });
  }

  /**
   * Listen for reveal events (random numbers delivered).
   */
  onReveal(callback: (event: RevealEvent) => void): void {
    this.contract.on('Revealed', (provider, caller, sequenceNumber, randomNumber, userContribution, providerContribution, callbackFailed, callbackReturnValue, callbackGasUsed) => {
      callback({
        provider,
        caller,
        sequenceNumber,
        randomNumber,
        userContribution,
        providerContribution,
        callbackFailed,
        callbackReturnValue,
        callbackGasUsed,
      });
    });
  }

  /**
   * Stop all event listeners.
   */
  removeAllListeners(): void {
    this.contract.removeAllListeners();
  }

  // ============================================================
  //                    UTILITY FUNCTIONS
  // ============================================================

  /**
   * Generate a random 32-byte value (for user contribution).
   */
  static generateUserRandom(): string {
    const crypto = require('crypto');
    return '0x' + crypto.randomBytes(32).toString('hex');
  }

  /**
   * Compute the user commitment from a random number.
   */
  static computeUserCommitment(userRandom: string): string {
    return ethers.keccak256(ethers.hexlify(userRandom));
  }

  /**
   * Construct a provider commitment from a revelation and the number of hashes.
   * Repeatedly hashes the revelation `numHashes` times.
   */
  static constructProviderCommitment(numHashes: number, revelation: string): string {
    let current = revelation;
    for (let i = 0; i < numHashes; i++) {
      current = ethers.keccak256(ethers.toBeHex(current));
    }
    return current;
  }

  /**
   * Generate a full hash chain from a seed.
   * @param seed The random seed (32 bytes hex)
   * @param length Number of values in the chain
   * @returns { commitment: x_0, revelations: [x_1, x_2, ...] }
   */
  static generateHashChain(seed: string, length: number): { commitment: string; revelations: string[] } {
    const revelations: string[] = [];
    let current = seed;
    // x_{length-1} = seed, x_i = hash(x_{i+1}), ..., x_0 = hash(x_1)
    for (let i = 0; i < length - 1; i++) {
      current = ethers.keccak256(ethers.hexlify(current));
      revelations.push(current);
    }
    // Reverse into commitment-first order: [x_0, x_1, ..., x_{n-2}].
    // The original seed is x_{n-1}, so append it as the final reveal value.
    revelations.reverse();

    return {
      commitment: revelations[0],
      revelations: revelations.slice(1).concat([seed]),
    };
  }

  /**
   * Combine user and provider random values.
   */
  static combineRandom(userRandom: string, providerRandom: string, blockHash: string = ethers.ZeroHash): string {
    return ethers.solidityPackedKeccak256(
      ['bytes32', 'bytes32', 'bytes32'],
      [userRandom, providerRandom, blockHash],
    );
  }
}

// Re-export ethers for convenience
export { ethers };