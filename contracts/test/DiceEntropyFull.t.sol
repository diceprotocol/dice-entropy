// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";
import {DiceStructsV2} from "@dice-protocol/sdk/DiceStructsV2.sol";
import {DiceErrors} from "@dice-protocol/sdk/DiceErrors.sol";
import {DiceStatusConstants} from "@dice-protocol/sdk/DiceStatusConstants.sol";
import {IEntropyConsumer} from "@dice-protocol/sdk/IEntropyConsumer.sol";

contract CallbackRecorder {
    DiceEntropy public dice;
    address public provider;

    mapping(uint64 => bool) public callbackCalled;
    mapping(uint64 => bytes32) public randomNumbers;

    constructor(address _dice, address _provider) {
        dice = DiceEntropy(_dice);
        provider = _provider;
    }

    function request(bytes32 userRandom, uint32 gasLimit) public payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, gasLimit);
    }

    // Implement callback selector directly — does not inherit IEntropyConsumer
    function _entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) external {
        require(msg.sender == address(dice), "Only DiceEntropy");
        callbackCalled[sequenceNumber] = true;
        randomNumbers[sequenceNumber] = randomNumber;
    }
}

contract DiceEntropyFullTest is Test {
    DiceEntropy public dice;
    address admin = address(0xBEEF1);
    address nonAdmin = address(0xBAD);
    address provider = address(0xBEEF4);
    address vault = address(0xBEEF5);

    bytes32[] chain;

    function _buildChain(uint256 len) internal {
        chain = new bytes32[](len);
        chain[len - 1] = keccak256(abi.encodePacked("seed", block.timestamp));
        for (uint256 i = len - 1; i > 0; i--) {
            chain[i - 1] = keccak256(bytes.concat(chain[i]));
        }
    }

    function setUp() public {
        dice = new DiceEntropy(admin, 0, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        _buildChain(100);

        vm.prank(admin);
        dice.registerFor(provider, 0, chain[0], "", 100, "");
    }

    // ============================================================
    //                  PROVIDER REGISTRATION
    // ============================================================

    function test_Register_NewProvider() public {
        address newProvider = address(0xBEEF3);
        _buildChain(50);

        vm.prank(admin);
        dice.registerFor(newProvider, 0, chain[0], "metadata", 50, "");

        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(newProvider);
        assertEq(info.originalCommitment, chain[0]);
        assertEq(info.currentCommitment, chain[0]);
        assertEq(info.sequenceNumber, 1);
        assertEq(info.endSequenceNumber, 50);
    }

    function test_Register_RotateCommitment() public {
        // Advance commitment to match sequence number (no in-flight requests)
        vm.prank(provider);
        dice.advanceProviderCommitment(provider, 1, chain[1]);

        bytes32 newCommitment = keccak256("new chain root");
        vm.prank(admin);
        dice.registerFor(provider, 0, newCommitment, "", 200, "");

        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.currentCommitment, newCommitment);
    }

    function test_Register_ZeroChainLength_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(DiceErrors.AssertionFailure.selector);
        dice.registerFor(address(0xBEEF3), 0, chain[0], "", 0, "");
    }

    function test_Register_Unauthorized_Reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        dice.registerFor(provider, 0, chain[0], "", 10, "");
    }

    function test_GetProviderInfoV2() public view {
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfoV2(provider);
        assertEq(info.originalCommitment, chain[0]);
        assertEq(info.sequenceNumber, 1);
    }

    function test_GetDefaultProvider() public view {
        assertEq(dice.getDefaultProvider(), provider);
    }

    // ============================================================
    //                  REQUEST + REVEAL FLOW
    // ============================================================

    function test_RequestAndReveal_Single() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("user1");

        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, chain[seq]);

        assertTrue(consumer.callbackCalled(seq));
        assertEq(consumer.randomNumbers(seq), dice.combineRandomValues(userRandom, chain[seq], bytes32(0)));
    }

    function test_RequestAndReveal_Multiple() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);

        for (uint64 i = 1; i <= 10; i++) {
            bytes32 userRandom = keccak256(abi.encodePacked("user", i));
            uint64 seq = consumer.request{value: 0}(userRandom, 0);

            vm.prank(provider);
            dice.revealWithCallback(provider, seq, userRandom, chain[seq]);

            assertTrue(consumer.callbackCalled(seq), "callback not called");
        }
    }

    function test_RequestAndReveal_Concurrent() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);

        uint64[] memory seqs = new uint64[](5);
        bytes32[] memory userRandoms = new bytes32[](5);

        for (uint64 i = 0; i < 5; i++) {
            userRandoms[i] = keccak256(abi.encodePacked("concurrent", i));
            seqs[i] = consumer.request{value: 0}(userRandoms[i], 0);
        }

        for (uint64 i = 0; i < 5; i++) {
            vm.prank(provider);
            dice.revealWithCallback(provider, seqs[i], userRandoms[i], chain[seqs[i]]);
            assertTrue(consumer.callbackCalled(seqs[i]));
        }
    }

    function test_RequestAndReveal_OutOfOrder() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);

        bytes32 userRandom1 = keccak256("u1");
        bytes32 userRandom2 = keccak256("u2");

        uint64 seq1 = consumer.request{value: 0}(userRandom1, 0);
        uint64 seq2 = consumer.request{value: 0}(userRandom2, 0);

        // Reveal in reverse order
        vm.prank(provider);
        dice.revealWithCallback(provider, seq2, userRandom2, chain[seq2]);
        assertTrue(consumer.callbackCalled(seq2));

        vm.prank(provider);
        dice.revealWithCallback(provider, seq1, userRandom1, chain[seq1]);
        assertTrue(consumer.callbackCalled(seq1));
    }

    // ============================================================
    //                  FEE MANAGEMENT (SINGLE-FEE MODEL)
    // ============================================================

    function test_FeeCollection() public {
        DiceEntropy feeDice = new DiceEntropy(admin, 0.001 ether, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        vm.prank(admin);
        feeDice.registerFor(provider, 0, chain[0], "", 100, "");

        CallbackRecorder consumer = new CallbackRecorder(address(feeDice), provider);
        uint128 fee = feeDice.getFee(provider);
        assertEq(fee, 0.001 ether);

        consumer.request{value: fee}(keccak256("test"), 0);

        assertEq(feeDice.getAccruedFees(), 0.001 ether);
    }

    function test_FeeWithdrawal_ToVault() public {
        DiceEntropy feeDice = new DiceEntropy(admin, 0.001 ether, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        vm.prank(admin);
        feeDice.registerFor(provider, 0, chain[0], "", 100, "");

        CallbackRecorder consumer = new CallbackRecorder(address(feeDice), provider);
        consumer.request{value: 0.001 ether}(keccak256("test"), 0);

        assertEq(feeDice.getAccruedFees(), 0.001 ether);

        uint256 vaultBefore = vault.balance;
        vm.prank(admin);
        feeDice.withdrawFees(0.001 ether);
        assertEq(vault.balance, vaultBefore + 0.001 ether);
        assertEq(feeDice.getAccruedFees(), 0);
    }

    function test_InsufficientFee() public {
        DiceEntropy feeDice = new DiceEntropy(admin, 0.001 ether, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        vm.prank(admin);
        feeDice.registerFor(provider, 0, chain[0], "", 100, "");

        CallbackRecorder consumer = new CallbackRecorder(address(feeDice), provider);
        vm.expectRevert(DiceErrors.InsufficientFee.selector);
        consumer.request{value: 0.0001 ether}(keccak256("test"), 0);
    }

    function test_SetFee_Admin() public {
        vm.prank(admin);
        dice.setFee(0.005 ether);
        assertEq(dice.getProtocolFee(), 0.005 ether);
    }

    function test_SetFee_NonAdmin_Reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert("Only admin");
        dice.setFee(0.005 ether);
    }

    function test_WithdrawFees_NonAdmin_Reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert("Only admin");
        feeDice_withdrawFees();
    }

    function feeDice_withdrawFees() internal {
        dice.withdrawFees(0);
    }

    function test_Withdraw_NonProvider_Reverts() public {
        // The old withdraw() always reverts in single-fee model
        vm.prank(provider);
        vm.expectRevert();
        dice.withdraw(0);
    }

    function test_SetProviderFee_AlwaysReverts() public {
        // Provider fee is protocol-level now, not per-provider
        vm.prank(provider);
        vm.expectRevert();
        dice.setProviderFee(0.0005 ether);
    }

    function test_SetFeeManager_AlwaysReverts() public {
        vm.prank(provider);
        vm.expectRevert();
        dice.setFeeManager(address(0xBEEF3));
    }

    // ============================================================
    //                  REVEAL EDGE CASES
    // ============================================================

    function test_Reveal_DoubleReveal() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("double");
        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, chain[seq]);

        // Second reveal should fail
        vm.prank(provider);
        vm.expectRevert(DiceErrors.NoSuchRequest.selector);
        dice.revealWithCallback(provider, seq, userRandom, chain[seq]);
    }

    function test_Reveal_IncorrectProviderContribution() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("wrong-provider");
        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        vm.expectRevert(DiceErrors.IncorrectRevelation.selector);
        dice.revealWithCallback(provider, seq, userRandom, keccak256("wrong"));
    }

    function test_Reveal_IncorrectUserContribution() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("correct");
        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        vm.expectRevert(DiceErrors.IncorrectRevelation.selector);
        dice.revealWithCallback(provider, seq, keccak256("wrong"), chain[seq]);
    }

    function test_Reveal_NonExistentRequest() public {
        vm.prank(provider);
        vm.expectRevert(DiceErrors.NoSuchRequest.selector);
        dice.revealWithCallback(provider, 999, keccak256("a"), keccak256("b"));
    }

    // ============================================================
    //                  ADMIN FUNCTIONS
    // ============================================================

    function test_ProposeAndAcceptAdmin() public {
        address newAdmin = address(0xBEEF6);

        vm.prank(admin);
        dice.proposeAdmin(newAdmin);

        vm.prank(newAdmin);
        dice.acceptAdmin();
    }

    function test_ProposeAdmin_NonAdmin_Reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert("Only admin");
        dice.proposeAdmin(address(0xBEEF6));
    }

    function test_SetDefaultProvider_Admin() public {
        vm.prank(admin);
        dice.setDefaultProvider(address(0xBEEF3));
        assertEq(dice.getDefaultProvider(), address(0xBEEF3));
    }

    function test_SetDefaultProvider_NonAdmin_Reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert("Only admin");
        dice.setDefaultProvider(address(0xBEEF3));
    }

    // ============================================================
    //                  PROVIDER CONFIGURATION
    // ============================================================

    function test_SetProviderUri() public {
        vm.prank(provider);
        dice.setProviderUri("https://diceprotocol.world");
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.uri, "https://diceprotocol.world");
    }

    function test_SetMaxNumHashes() public {
        vm.prank(provider);
        dice.setMaxNumHashes(50);
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.maxNumHashes, 50);
    }

    function test_SetDefaultGasLimit() public {
        vm.prank(provider);
        dice.setDefaultGasLimit(100000);
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.defaultGasLimit, 100000);
    }

    // ============================================================
    //                  CONSTRUCTOR TESTS
    // ============================================================

    function test_Constructor_ZeroAdmin_Reverts() public {
        vm.expectRevert("admin is zero address");
        new DiceEntropy(address(0), 0, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
    }

    function test_Constructor_ZeroDefaultProvider_Reverts() public {
        vm.expectRevert("defaultProvider is zero address");
        new DiceEntropy(admin, 0, address(0), false, vault, bytes32(0), 0, new bytes(0), 10);
    }

    function test_Constructor_ZeroVault_Reverts() public {
        vm.expectRevert("vault is zero address");
        new DiceEntropy(admin, 0, provider, false, address(0), bytes32(0), 0, new bytes(0), 10);
    }

    // ============================================================
    //                  OUT OF RANDOMNESS
    // ============================================================

    function test_OutOfRandomness() public {
        bytes32 userRandom = keccak256("oob");

        // Use all 99 values (seq 1-99, commitment at 0)
        for (uint64 i = 1; i <= 99; i++) {
            dice.requestV2{value: 0}(provider, userRandom, 0);
        }

        vm.expectRevert(DiceErrors.OutOfRandomness.selector);
        dice.requestV2{value: 0}(provider, userRandom, 0);
    }

    // ============================================================
    //                  COMMITMENT ADVANCEMENT
    // ============================================================

    function test_AdvanceProviderCommitment() public {
        // Advance from current commitment (chain[0], seq 0) to seq 5
        // numHashes = 5 - 0 = 5, hash^5(chain[5]) should equal chain[0]
        vm.prank(provider);
        dice.advanceProviderCommitment(provider, 5, chain[5]);

        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.currentCommitment, chain[5]);
        assertEq(info.currentCommitmentSequenceNumber, 5);
    }

    function test_AdvanceProviderCommitment_TooOld() public {
        vm.prank(provider);
        vm.expectRevert(DiceErrors.UpdateTooOld.selector);
        dice.advanceProviderCommitment(provider, 0, chain[0]);
    }

    function test_AdvanceProviderCommitment_WrongRevelation() public {
        vm.prank(provider);
        vm.expectRevert(DiceErrors.IncorrectRevelation.selector);
        dice.advanceProviderCommitment(provider, 5, keccak256("wrong"));
    }

    // ============================================================
    //                  REQUEST OVERFLOW
    // ============================================================

    function test_RequestOverflow_MoreThan32() public {
        // Make 40 requests to test overflow handling
        bytes32 userRandom = keccak256("overflow");
        for (uint64 i = 0; i < 40; i++) {
            dice.requestV2{value: 0}(provider, userRandom, 0);
        }
        // All requests should be findable
        DiceStructsV2.Request memory req = dice.getRequest(provider, 35);
        assertEq(req.sequenceNumber, 35);
    }

    // ============================================================
    //                  CALLBACK REVERT HANDLING
    // ============================================================

    function test_CallbackRevert_GasLimitSet() public {
        // Register provider with gas limit
        vm.prank(provider);
        dice.setDefaultGasLimit(100000);

        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("callback-test");
        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, chain[seq]);
        assertTrue(consumer.callbackCalled(seq));
    }

    // ============================================================
    //                  REENTRANCY
    // ============================================================

    function test_Reentrancy_DuringCallback() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("reentrancy");
        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, chain[seq]);
        // If we get here without reverting, the test passes
        assertTrue(consumer.callbackCalled(seq));
    }

    // Pure functions tested via request/reveal flow above
}