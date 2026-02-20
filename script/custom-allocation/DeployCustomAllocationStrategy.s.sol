// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CustomAllocationStrategy} from "src/custom-allocation/CustomAllocationStrategy.sol";
import {Log} from "../common/Log.sol";

contract DeployCustomAllocationStrategyScript is Script, Log {
    // NOTE: change this for respective network
    address public constant LIQUIDITY_LAUNCHER = 0x00000008412db3394C91A5CbD01635c6d140637C;

    function run() public {
        vm.startBroadcast();

        CustomAllocationStrategy strategy_ = new CustomAllocationStrategy(LIQUIDITY_LAUNCHER);
        recordDeployment(address(strategy_), "CustomAllocationStrategy");
        vm.stopBroadcast();
    }
}
