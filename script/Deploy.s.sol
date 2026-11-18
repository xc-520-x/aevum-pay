// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AevumPay} from "../src/AevumPay.sol";

contract Deploy is Script {
    // tUSD8 on QDay Aevum testnet (chain ID 44005).
    address constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external returns (AevumPay pay) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(key);
        pay = new AevumPay(TUSD8);
        vm.stopBroadcast();
        console.log("AevumPay deployed at:", address(pay));
    }
}
