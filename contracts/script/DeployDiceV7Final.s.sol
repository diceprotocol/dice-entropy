// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@dice-protocol/DiceEntropy.sol";

/// @notice v7 FINAL deployment: keeper deploys as temporary admin, registers provider,
///         then transfers admin to the real admin wallet.
contract DeployDiceV7Final is Script {
    function run() external {
        uint256 pk = vm.envUint("PK");
        address keeper = vm.addr(pk);
        
        vm.startBroadcast(pk);
        
        // Deploy with keeper as temporary admin
        DiceEntropy dice = new DiceEntropy(
            keeper,                                           // temporary admin (keeper)
            25000000000000,                                   // fee (0.000025 ETH)
            keeper,                                           // defaultProvider (keeper)
            false,                                             // prefillRequestStorage
            0x918EAF0b2589710B0D85ef48C12a343E68263841,      // vault
            bytes32(0),                                        // commitment (empty)
            0,                                                 // chainLength=0 (no auto-register)
            bytes(""),                                          // commitmentMetadata
            6                                             // refundDelayBlocks
        );
        
        console.log("DiceEntropy v7 deployed at:", address(dice));
        
        // Register provider — commitment will be set via cast after we know the address
        // (commitment depends on the contract address through generate_secret)
        
        // Transfer admin to real admin
        dice.proposeAdmin(0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD);
        
        console.log("Admin proposed to: 0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD");
        console.log("Next: call registerFor + acceptAdmin from admin wallet");
        
        vm.stopBroadcast();
    }
}
