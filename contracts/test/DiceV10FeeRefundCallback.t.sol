// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";
import {DiceStructsV2} from "@dice-protocol/sdk/DiceStructsV2.sol";
import {DiceErrors} from "@dice-protocol/sdk/DiceErrors.sol";
import {DiceEventsV2} from "@dice-protocol/sdk/DiceEventsV2.sol";
import {DiceStatusConstants} from "@dice-protocol/sdk/DiceStatusConstants.sol";

contract GoodConsumer {
    DiceEntropy public dice;
    address public provider;

    mapping(uint64 => bool) public callbackCalled;
    mapping(uint64 => bytes32) public randomNumbers;

    constructor(address _dice, address _provider) {
        dice = DiceEntropy(_dice);
        provider = _provider;
    }

    function request(bytes32 userRandom, uint32 gasLimit) external payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, gasLimit);
    }

    function _entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) external {
        require(msg.sender == address(dice), "Only DiceEntropy");
        callbackCalled[sequenceNumber] = true;
        randomNumbers[sequenceNumber] = randomNumber;
    }
}

contract RevertingConsumer {
    DiceEntropy public dice;
    address public provider;

    constructor(address _dice, address _provider) {
        dice = DiceEntropy(_dice);
        provider = _provider;
    }

    function request(bytes32 userRandom, uint32 gasLimit) external payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, gasLimit);
    }

    function _entropyCallback(uint64, address, bytes32) external pure {
        revert("callback boom");
    }
}

contract DiceV10FeeRefundCallbackTest is Test {
    DiceEntropy public dice;
    address admin = address(0xA11CE);
    address provider = address(0xBEEF4);
    address vault = address(0xBEEF5);
    address requester = address(0xBEEF6);
    address stranger = address(0xBEEF7);

    uint64 constant REFUND_DELAY = 10;
    uint128 constant FEE = 0.001 ether;

    // Hash chain: x3 -> x2 -> x1 -> x0 (commitment)
    bytes32 x0;
    bytes32 x1;
    bytes32 x2;
    bytes32 x3;

    function setUp() public {
        dice = new DiceEntropy(admin, FEE, provider, false, vault, bytes32(0), 0, new bytes(0), REFUND_DELAY);

        x3 = keccak256("secret seed v10");
        x2 = keccak256(bytes.concat(x3));
        x1 = keccak256(bytes.concat(x2));
        x0 = keccak256(bytes.concat(x1));

        vm.prank(admin);
        dice.registerFor(provider, 0, x0, "", 8, "");

        vm.deal(requester, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    // ============================================================
    //                         FEE BEHAVIOR
    // ============================================================

    function test_Fee_ExactPaymentSucceeds() public {
        bytes32 userRandom = keccak256("fee-exact");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);
        assertEq(seq, 1);
        assertEq(dice.getAccruedFees(), FEE);
        assertEq(dice.getProtocolFee(), FEE);

        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.feePaid, FEE);
        assertEq(req.requester, requester);
    }

    function test_Fee_UnderpayReverts() public {
        bytes32 userRandom = keccak256("fee-under");
        vm.prank(requester);
        vm.expectRevert(DiceErrors.InsufficientFee.selector);
        dice.requestV2{value: FEE - 1}(provider, userRandom, 0);
    }

    function test_Fee_OverpayReverts() public {
        bytes32 userRandom = keccak256("fee-over");
        vm.prank(requester);
        vm.expectRevert(DiceErrors.InsufficientFee.selector);
        dice.requestV2{value: FEE + 1}(provider, userRandom, 0);
    }

    function test_Fee_SetFeeUpdatesFutureRequestsOnly() public {
        bytes32 userRandom = keccak256("fee-change");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        uint128 newFee = 0.002 ether;
        vm.prank(admin);
        dice.setFee(newFee);
        assertEq(dice.getProtocolFee(), newFee);

        // Old request still stores original feePaid
        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.feePaid, FEE);

        // Future request requires new fee
        vm.prank(requester);
        vm.expectRevert(DiceErrors.InsufficientFee.selector);
        dice.requestV2{value: FEE}(provider, keccak256("next"), 0);

        vm.prank(requester);
        uint64 seq2 = dice.requestV2{value: newFee}(provider, keccak256("next-ok"), 0);
        DiceStructsV2.Request memory req2 = dice.getRequest(provider, seq2);
        assertEq(req2.feePaid, newFee);
    }

    // ============================================================
    //                        REFUND BEHAVIOR
    // ============================================================

    function test_Refund_CannotBeforeTimeout() public {
        bytes32 userRandom = keccak256("refund-early");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        vm.prank(requester);
        vm.expectRevert(DiceErrors.RefundNotAvailable.selector);
        dice.refundRequest(provider, seq);
    }

    function test_Refund_NonRequesterCannotRefund() public {
        bytes32 userRandom = keccak256("refund-auth");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        vm.roll(block.number + REFUND_DELAY);

        vm.prank(stranger);
        vm.expectRevert(DiceErrors.Unauthorized.selector);
        dice.refundRequest(provider, seq);
    }

    function test_Refund_AfterTimeoutSucceedsAndClearsRequest() public {
        bytes32 userRandom = keccak256("refund-ok");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        uint256 requesterBefore = requester.balance;
        uint128 accruedBefore = dice.getAccruedFees();
        assertEq(accruedBefore, FEE);

        vm.roll(block.number + REFUND_DELAY);

        vm.expectEmit(true, true, true, true);
        emit DiceEventsV2.RequestRefunded(provider, requester, seq, FEE, bytes(""));

        vm.prank(requester);
        dice.refundRequest(provider, seq);

        assertEq(requester.balance, requesterBefore + FEE);
        assertEq(dice.getAccruedFees(), 0);

        // Request cleared
        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.sequenceNumber, 0);
    }

    function test_Refund_UsesFeePaidAtRequestTimeEvenIfFeeChanged() public {
        bytes32 userRandom = keccak256("refund-old-fee");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        // Admin raises fee after request
        vm.prank(admin);
        dice.setFee(0.005 ether);

        vm.roll(block.number + REFUND_DELAY);

        uint256 requesterBefore = requester.balance;
        vm.prank(requester);
        dice.refundRequest(provider, seq);

        // Refunds original FEE, not the new fee
        assertEq(requester.balance, requesterBefore + FEE);
        assertEq(dice.getAccruedFees(), 0);
    }

    function test_Refund_RevealAfterRefundReverts() public {
        bytes32 userRandom = keccak256("refund-then-reveal");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        vm.roll(block.number + REFUND_DELAY);
        vm.prank(requester);
        dice.refundRequest(provider, seq);

        vm.prank(provider);
        vm.expectRevert(DiceErrors.NoSuchRequest.selector);
        dice.revealWithCallback(provider, seq, userRandom, x1);
    }

    function test_Refund_DoubleRefundReverts() public {
        bytes32 userRandom = keccak256("refund-double");
        vm.prank(requester);
        uint64 seq = dice.requestV2{value: FEE}(provider, userRandom, 0);

        vm.roll(block.number + REFUND_DELAY);
        vm.prank(requester);
        dice.refundRequest(provider, seq);

        vm.prank(requester);
        vm.expectRevert(DiceErrors.NoSuchRequest.selector);
        dice.refundRequest(provider, seq);
    }

    function test_GetRefundDelayBlocks() public view {
        assertEq(dice.getRefundDelayBlocks(), REFUND_DELAY);
    }

    // ============================================================
    //                       CALLBACK BEHAVIOR
    // ============================================================

    function test_Callback_SuccessClearsRequest() public {
        // Enable gas-limited callback path
        vm.prank(provider);
        dice.setDefaultGasLimit(100_000);

        GoodConsumer consumer = new GoodConsumer(address(dice), provider);
        vm.deal(address(consumer), 1 ether);

        bytes32 userRandom = keccak256("cb-ok");
        uint64 seq = consumer.request{value: FEE}(userRandom, 200_000);

        vm.prank(provider);
        dice.revealWithCallback(provider, seq, userRandom, x1);

        assertTrue(consumer.callbackCalled(seq));
        assertTrue(consumer.randomNumbers(seq) != bytes32(0));

        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.sequenceNumber, 0);
    }

    function test_Callback_RevertWithEnoughGasMarksFailedAndKeepsRequest() public {
        // Enable gas-limited callback path so failed callbacks can be recorded.
        vm.prank(provider);
        dice.setDefaultGasLimit(100_000);

        RevertingConsumer consumer = new RevertingConsumer(address(dice), provider);
        vm.deal(address(consumer), 1 ether);

        bytes32 userRandom = keccak256("cb-fail");
        uint64 seq = consumer.request{value: FEE}(userRandom, 200_000);

        // Provide ample gas so the safe-call gas condition is satisfied.
        vm.prank(provider);
        dice.revealWithCallback{gas: 1_000_000}(provider, seq, userRandom, x1);

        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.sequenceNumber, seq);
        assertEq(req.callbackStatus, DiceStatusConstants.CALLBACK_FAILED);
    }

    function test_Callback_InsufficientGasReverts() public {
        // Enable gas-limited callback path.
        vm.prank(provider);
        dice.setDefaultGasLimit(200_000);

        RevertingConsumer consumer = new RevertingConsumer(address(dice), provider);
        vm.deal(address(consumer), 1 ether);

        bytes32 userRandom = keccak256("cb-gas");
        uint64 seq = consumer.request{value: FEE}(userRandom, 200_000);

        // Too little gas remaining for the requested callback gas limit.
        vm.prank(provider);
        vm.expectRevert(DiceErrors.InsufficientGas.selector);
        dice.revealWithCallback{gas: 50_000}(provider, seq, userRandom, x1);

        // Request still active
        DiceStructsV2.Request memory req = dice.getRequest(provider, seq);
        assertEq(req.sequenceNumber, seq);
        assertEq(req.callbackStatus, DiceStatusConstants.CALLBACK_NOT_STARTED);
    }
}
