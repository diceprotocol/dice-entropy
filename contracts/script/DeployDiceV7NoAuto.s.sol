// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@dice-protocol/DiceEntropy.sol";

/// @notice v7 deployment script — deploys contract WITHOUT auto-registration.
/// Provider will be registered separately via registerFor after computing
/// the hash chain commitment from the new contract address.
contract DeployDiceV7NoAuto is Script {
    function run() external {
        uint256 pk = vm.envUint("PK");
        vm.startBroadcast(pk);
        
        DiceEntropy dice = new DiceEntropy(
            0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD,  // admin
            25000000000000,                                 // fee (0.000025 ETH)
            0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6,    // defaultProvider (keeper)
            false,                                           // prefillRequestStorage
            0x918EAF0b2589710B0D85ef48C12a343E68263841,    // vault
            bytes32(0),                                      // commitment (empty — no auto-register)
            0,                                               // chainLength=0 (no auto-register)
            bytes(""),                                       // commitmentMetadata
            6                                               // refundDelayBlocks
        );
        
        console.log("DiceEntropy v7 (no auto-register) deployed at:", address(dice));
        vm.stopBroadcast();
    }
}
