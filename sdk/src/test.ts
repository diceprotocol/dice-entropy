/**
 * Quick smoke test — verifies the SDK can read from the testnet contract.
 */
const { DiceProtocol, ethers } = require('./index');

async function main() {
  const dice = new DiceProtocol({
    rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
    contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
  });

  console.log('Contract:', dice.getAddress());

  // Read default provider
  const defaultProvider = await dice.getDefaultProvider();
  console.log('Default Provider:', defaultProvider);

  // Read protocol fee
  const protocolFee = await dice.getProtocolFee();
  console.log('Protocol Fee:', protocolFee.toString(), 'wei');

  // Read the fee for a callback gas limit, as requestRandom() does before every request
  const feeWithGas = await dice.getFee(defaultProvider, 200000);
  console.log('Fee for 200,000 callback gas:', feeWithGas.toString(), 'wei');
  if (feeWithGas !== protocolFee) throw new Error(`Unexpected fee for a gas limit: ${feeWithGas}`);

  // Read provider info
  const info = await dice.getProviderInfo(defaultProvider);
  console.log('Provider Info:');
  console.log('  Fee:', info.feeInWei.toString(), 'wei');
  console.log('  Sequence:', info.sequenceNumber.toString());
  console.log('  End Sequence:', info.endSequenceNumber.toString());
  console.log('  Commitment:', info.currentCommitment);
  console.log('  Chain remaining:', (info.endSequenceNumber - info.sequenceNumber).toString());

  // Read accrued treasury fees
  const accrued = await dice.getAccruedTreasuryFees();
  console.log('Accrued Treasury Fees:', accrued.toString(), 'wei');

  // Test utility functions
  const userRandom = DiceProtocol.generateUserRandom();
  console.log('\nGenerated user random:', userRandom);
  const commitment = DiceProtocol.computeUserCommitment(userRandom);
  console.log('User commitment:', commitment);

  // Test hash chain generation
  const chain = DiceProtocol.generateHashChain('0x' + 'ab'.repeat(32), 10);
  console.log('\nHash chain (10 values):');
  console.log('  Commitment (x_0):', chain.commitment);
  console.log('  First reveal (x_1):', chain.revelations[0]);
  console.log('  Last (x_9 = seed):', chain.revelations[8]);
  if (protocolFee !== 25000000000000n) throw new Error(`Unexpected protocol fee: ${protocolFee}`);
  if (info.endSequenceNumber <= info.sequenceNumber) throw new Error('Provider hash chain exhausted');
  if (chain.revelations.length !== 9) throw new Error(`Expected 9 reveal values, got ${chain.revelations.length}`);
  if (chain.revelations[8] !== '0x' + 'ab'.repeat(32)) throw new Error('Hash-chain final reveal should equal seed');

  // A revelation is a bytes32: one that starts with a zero byte is still hashed as 32 bytes, as the contract does.
  // About one value in 256 does; here the seed (the last reveal) is one of them.
  const zeroLed = DiceProtocol.generateHashChain('0x00' + 'ab'.repeat(31), 4);
  zeroLed.revelations.forEach((reveal: string, i: number) => {
    if (DiceProtocol.constructProviderCommitment(i + 1, reveal) !== zeroLed.commitment) {
      throw new Error(`Reveal ${i + 1} (${reveal}) does not hash back to the commitment`);
    }
  });

  console.log('\n✅ SDK smoke test passed');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
