// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@dice-protocol/DiceEntropy.sol";

/// @notice Dice Protocol v10 deployment rehearsal script.
/// @dev Deploy with a tiny nonzero fee for live E2E, then set final fee after verification.
///      DO NOT broadcast without explicit approval.
///
/// Expected constructor args for live test deploy:
/// - feeInWei: 1 wei (tiny nonzero for free testing)
/// - refundDelayBlocks: 6 (~72s on Robinhood L1 blocks ~12s)
/// - chainLength / commitment: set after computing provider commitment for new address,
///   or deploy with empty commitment and registerFor afterwards.
contract DeployDiceV10 is Script {
    function run() external {
        uint256 pk = vm.envUint("PK");
        address admin = vm.envAddress("DICE_ADMIN");
        address vault = vm.envAddress("DICE_VAULT");
        address defaultProvider = vm.envAddress("DICE_DEFAULT_PROVIDER");

        // Tiny nonzero fee for live E2E testing. Final fee set later via setFee.
        uint128 feeInWei = uint128(vm.envOr("DICE_FEE_WEI", uint256(1)));
        uint64 refundDelayBlocks = uint64(vm.envOr("DICE_REFUND_DELAY_BLOCKS", uint256(6)));

        // Optional auto-register values. Prefer empty + later registerFor when commitment
        // depends on the newly deployed contract address.
        bytes32 commitment = vm.envOr("DICE_PROVIDER_COMMITMENT", bytes32(0));
        uint64 chainLength = uint64(vm.envOr("DICE_PROVIDER_CHAIN_LENGTH", uint256(0)));

        vm.startBroadcast(pk);

        DiceEntropy dice = new DiceEntropy(
            admin,
            feeInWei,
            defaultProvider,
            false,
            vault,
            commitment,
            chainLength,
            bytes(""),
            refundDelayBlocks
        );

        console.log("DiceEntropy v10 deployed at:", address(dice));
        console.log("feeInWei:", uint256(feeInWei));
        console.log("refundDelayBlocks:", uint256(refundDelayBlocks));
        console.log("defaultProvider:", defaultProvider);
        console.log("admin:", admin);
        console.log("vault:", vault);

        vm.stopBroadcast();
    }
}
