// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@dice-protocol/DiceEntropy.sol";

/// @notice v7 deployment script for Dice Protocol with security fixes.
/// @dev Deploys the SAME contract with C1-C4 fixes applied.
///      Uses a fresh 50,000 hash chain from the SAME seed.
contract DeployDiceV7 is Script {
    function run() external {
        uint256 pk = vm.envUint("PK");
        vm.startBroadcast(pk);
        
        DiceEntropy dice = new DiceEntropy(
            0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD,  // admin
            25000000000000,                                 // fee (0.000025 ETH)
            0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6,    // defaultProvider (keeper)
            false,                                           // prefillRequestStorage
            0x918EAF0b2589710B0D85ef48C12a343E68263841,    // vault
            0x3ee6b22e39df32c239ead8bd91e9378e9c65da12e6ec17b782f43e825c75d713,  // commitment root (same seed, fresh chain)
            50000,                                           // chainLength
            bytes(""),                                       // commitmentMetadata: EMPTY
            6                                               // refundDelayBlocks
        );
        
        console.log("DiceEntropy v7 deployed at:", address(dice));
        vm.stopBroadcast();
    }
}
