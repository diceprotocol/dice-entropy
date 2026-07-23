// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";
import {DiceStructsV2} from "@dice-protocol/sdk/DiceStructsV2.sol";
import {DiceErrors} from "@dice-protocol/sdk/DiceErrors.sol";
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

contract CoinFlip {
    DiceEntropy public dice;
    address public provider;

    constructor(address _dice, address _provider) {
        dice = DiceEntropy(_dice);
        provider = _provider;
    }

    function flip(bytes32 userCommitment) public payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userCommitment, 0);
    }
}

contract DiceEntropyTest is Test {
    DiceEntropy public dice;
    address admin = address(0xBEEF1);
    address provider = address(0xBEEF4);
    address vault = address(0xBEEF5);

    // Hash chain: x3 -> x2 -> x1 -> x0 (commitment)
    bytes32 x0;
    bytes32 x1;
    bytes32 x2;
    bytes32 x3;

    function setUp() public {
        dice = new DiceEntropy(admin, 0, provider, false, vault, bytes32(0), 0, new bytes(0), 10);

        // Generate hash chain: x3 is random, x_i = hash(x_{i+1})
        x3 = keccak256("secret seed");
        x2 = keccak256(bytes.concat(x3));
        x1 = keccak256(bytes.concat(x2));
        x0 = keccak256(bytes.concat(x1));

        // Register provider (admin-only via registerFor)
        vm.prank(admin);
        dice.registerFor(provider, 0, x0, "", 4, "");
    }

    function test_ProviderRegistered() public view {
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.originalCommitment, x0);
        assertEq(info.currentCommitment, x0);
        assertEq(info.sequenceNumber, 1);
        assertEq(info.endSequenceNumber, 4);
    }

    function test_RequestAndRevealWithCallback() public {
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("test");

        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);
    }

    function test_RequestAndRevealNoCallback() public {
        // V2 always uses callback
        CallbackRecorder consumer = new CallbackRecorder(address(dice), provider);
        bytes32 userRandom = keccak256("test2");

        uint64 seq = consumer.request{value: 0}(userRandom, 0);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);
    }

    function test_ConstructUserCommitment() public view {
        bytes32 userRandom = keccak256("test");
        bytes32 commitment = dice.constructUserCommitment(userRandom);
        assertEq(commitment, keccak256(bytes.concat(userRandom)));
    }

    function test_CombineRandomValues() public view {
        bytes32 result = dice.combineRandomValues(keccak256("a"), keccak256("b"), bytes32(0));
        assertEq(result, keccak256(abi.encodePacked(keccak256("a"), keccak256("b"), bytes32(0))));
    }

    function test_IncorrectRevelation() public {
        bytes32 userRandom = keccak256("test3");
        uint64 seq = dice.requestV2{value: 0}(provider, userRandom, 0);

        vm.prank(address(this));
        vm.expectRevert(DiceErrors.IncorrectRevelation.selector);
        dice.revealWithCallback(provider, seq, userRandom, keccak256("wrong"));
    }

    function test_OutOfRandomness() public {
        bytes32 userRandom = keccak256("test4");
        // Exhaust all 3 values (seq 1-3, commitment is at 0)
        for (uint64 i = 0; i < 3; i++) {
            dice.requestV2{value: 0}(provider, userRandom, 0);
        }
        // 4th request should fail
        vm.expectRevert(DiceErrors.OutOfRandomness.selector);
        dice.requestV2{value: 0}(provider, userRandom, 0);
    }

    function test_FeeCollection() public {
        // Deploy with 0.001 ETH fee
        DiceEntropy diceWithFee = new DiceEntropy(admin, 0.001 ether, provider, false, vault, bytes32(0), 0, new bytes(0), 10);
        vm.prank(admin);
        diceWithFee.registerFor(provider, 0, x0, "", 4, "");

        CoinFlip flip = new CoinFlip(address(diceWithFee), provider);
        uint128 fee = diceWithFee.getFee(provider);
        assertEq(fee, 0.001 ether);

        flip.flip{value: fee}(keccak256("test"));

        // All fees go to single pool
        assertEq(diceWithFee.getAccruedFees(), 0.001 ether);

        // Admin withdraws to vault
        uint256 vaultBefore = vault.balance;
        vm.prank(admin);
        diceWithFee.withdrawFees(0.001 ether);
        assertEq(vault.balance, vaultBefore + 0.001 ether);
        assertEq(diceWithFee.getAccruedFees(), 0);
    }
}