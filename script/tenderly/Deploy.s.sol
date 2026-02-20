// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ContinuousClearingAuctionFactory} from "continuous-clearing-auction/src/ContinuousClearingAuctionFactory.sol";

import {UERC20Factory} from "liquidity-launcher/src/token-factories/uerc20-factory/factories/UERC20Factory.sol";
import {LBPStrategyBasicFactory} from "liquidity-launcher/src/distributionStrategies/LBPStrategyBasicFactory.sol";

import {TenderlyConstants} from "../common/TenderlyConstants.sol";

contract DeployScript is Script, TenderlyConstants {
    function run() public {
        vm.startBroadcast();

        UERC20Factory uerc20Factory_ = new UERC20Factory();
        LBPStrategyBasicFactory factory_ = new LBPStrategyBasicFactory{salt: bytes32(0)}(positionManager, poolManager);
        ContinuousClearingAuctionFactory auctionFactory_ = new ContinuousClearingAuctionFactory();

        console.log("UERC20Factory deployed to:", address(uerc20Factory_));
        console.log("LBPStrategyBasicFactory deployed to:", address(factory_));
        console.log("ContinuousClearingAuctionFactory deployed to:", address(auctionFactory_));

        vm.stopBroadcast();
    }
}
