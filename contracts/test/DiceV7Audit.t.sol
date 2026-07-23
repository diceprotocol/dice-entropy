// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DiceEntropy} from "@dice-protocol/DiceEntropy.sol";
import {DiceStructsV2} from "@dice-protocol/sdk/DiceStructsV2.sol";
import {DiceErrors} from "@dice-protocol/sdk/DiceErrors.sol";
import {DiceStatusConstants} from "@dice-protocol/sdk/DiceStatusConstants.sol";
import {IEntropyConsumer} from "@dice-protocol/sdk/IEntropyConsumer.sol";

/// @title RevertingConsumer
/// @dev A consumer whose callback always reverts. Used to test C3 fix:
///      excessivelySafeCall on the no-gas-limit retry path.
///      Does NOT inherit IEntropyConsumer because _entropyCallback is now
///      non-virtual. Instead, implements the callback selector directly.
contract RevertingConsumer {
    DiceEntropy public dice;
    address public provider;
    bool public callbackAttempted;

    constructor(address _dice, address _provider) {
        dice = DiceEntropy(_dice);
        provider = _provider;
    }

    function request(bytes32 userRandom) public payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, 0);
    }

    // Mimic IEntropyConsumer._entropyCallback selector for the callback
    function _entropyCallback(uint64, address, bytes32) external {
        require(msg.sender == address(dice), "Only DiceEntropy");
        callbackAttempted = true;
        revert("callback always reverts");
    }
}

/// @title V7 Audit Fix Tests
/// @dev Tests for the four security fixes applied in the v7 contract:
///      C1: No-arg random() overloads removed (must revert)
///      C2: registerFor guards against in-flight requests
///      C3: Retry callback uses excessivelySafeCall
///      C4: proposeAdmin rejects address(0)
contract DiceV7AuditTest is Test {
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
    // C1: No-arg random() overloads must revert
    // ============================================================

    function testRevert_C1_NoArgRequestV2_Reverts() public {
        vm.expectRevert();
        dice.requestV2();
    }

    function testRevert_C1_NoArgRequestV2_GasLimit_Reverts() public {
        vm.expectRevert();
        dice.requestV2(uint32(100000));
    }

    function testRevert_C1_NoArgRequestV2_ProviderGasLimit_Reverts() public {
        vm.expectRevert();
        dice.requestV2(provider, uint32(100000));
    }

    // ============================================================
    // C2: registerFor guards against in-flight requests
    // ============================================================

    function testRevert_C2_RegisterFor_InFlightRequests() public {
        // Create a request that's in-flight (not yet revealed)
        bytes32 userRandom = keccak256("user-random");
        vm.deal(address(this), 1 ether);
        dice.requestV2{value: 0}(provider, userRandom, 0);

        // Attempt to re-register provider while request is in-flight
        _buildChain(50);
        vm.prank(admin);
        vm.expectRevert(bytes("in-flight requests exist"));
        dice.registerFor(provider, 0, chain[0], "", 50, "");
    }

    function test_C2_RegisterFor_AllowedWhenNoInFlight() public {
        // Advance commitment to match sequence number (no in-flight requests)
        vm.prank(provider);
        dice.advanceProviderCommitment(provider, 1, chain[1]);

        // Re-registration should succeed now
        _buildChain(50);
        vm.prank(admin);
        dice.registerFor(provider, 0, chain[0], "", 50, "");

        // Verify new commitment is set
        DiceStructsV2.ProviderInfo memory info = dice.getProviderInfo(provider);
        assertEq(info.originalCommitment, chain[0]);
    }

    function testRevert_C2_RegisterFor_ZeroAddress_Reverts() public {
        _buildChain(50);
        vm.prank(admin);
        vm.expectRevert(DiceErrors.AssertionFailure.selector);
        dice.registerFor(address(0), 0, chain[0], "", 50, "");
    }

    // ============================================================
    // C3: Retry callback uses excessivelySafeCall (reverting callback doesn't break reveal)
    // ============================================================

    function test_C3_RevertingCallback_NoGasLimit_DoesNotRevertReveal() public {
        // Deploy a consumer that always reverts in its callback
        RevertingConsumer consumer = new RevertingConsumer(address(dice), provider);

        // Set a fee so the consumer needs to pay
        vm.prank(admin);
        dice.setFee(0.000055 ether);

        // Request randomness with gasLimit=0 (triggers the else branch / no-gas-limit path)
        bytes32 userRandom = keccak256("user-random");
        vm.deal(address(consumer), 1 ether);
        uint64 seqNum = consumer.request{value: 0.000055 ether}(userRandom);

        // Compute the reveal values
        bytes32 userContribution = userRandom;
        bytes32 providerContribution = chain[1];

        // This should NOT revert even though the callback reverts.
        // The excessivelySafeCall catches the revert in the consumer's callback.
        dice.revealWithCallback(provider, seqNum, userContribution, providerContribution);

        // If we reach here, the test passes — the reveal succeeded despite
        // a reverting callback.
        assertTrue(true, "Reveal succeeded despite reverting callback");
    }

    // ============================================================
    // C4: proposeAdmin rejects address(0)
    // ============================================================

    function testRevert_C4_ProposeAdmin_ZeroAddress_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("admin is zero address"));
        dice.proposeAdmin(address(0));
    }

    function test_C4_ProposeAdmin_ValidAddress_Succeeds() public {
        address newAdmin = address(0xBEEF6);
        vm.prank(admin);
        dice.proposeAdmin(newAdmin);

        // Accept admin
        vm.prank(newAdmin);
        dice.acceptAdmin();

        // Verify admin changed
        vm.prank(newAdmin);
        dice.setFee(0.0001 ether); // Should not revert
    }
}
