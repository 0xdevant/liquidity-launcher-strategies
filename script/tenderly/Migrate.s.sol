// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {
    IContinuousClearingAuction
} from "lib/continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {ICheckpointStorage} from "continuous-clearing-auction/src/interfaces/ICheckpointStorage.sol";

import {LBPStrategyBasicFactory} from "liquidity-launcher/src/distributionStrategies/LBPStrategyBasicFactory.sol";
import {LBPStrategyBasic} from "liquidity-launcher/src/distributionContracts/LBPStrategyBasic.sol";
import {IDistributionContract} from "liquidity-launcher/src/interfaces/IDistributionContract.sol";

import {TenderlyConstants} from "../common/TenderlyConstants.sol";

interface ILBPStrategyBasic {
    function migrate() external;

    function migrationBlock() external view returns (uint64);
}

contract MigrateTenderlyScript is Script, TenderlyConstants, Test {
    // NOTE: change AUCTION & LBP_STRATEGY_BASIC for every new auction!
    IContinuousClearingAuction public auction = IContinuousClearingAuction(AUCTION);
    ILBPStrategyBasic public lbp = ILBPStrategyBasic(LBP_STRATEGY_BASIC);

    function run() public {
        vm.startBroadcast();
        // // move to auction end
        vm.rpc("evm_increaseBlocks", "[\"0x444\"]");

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");

        // move to migration block
        vm.rpc("evm_increaseBlocks", "[\"0x222\"]");
        lbp.migrate();

        // get latest clearing price
        auction.checkpoint();
        uint256 latestClearingPrice = ICheckpointStorage(address(auction)).clearingPrice();
        uint256 latestCurrencyRaised = auction.currencyRaised();

        emit log_named_uint("latestClearingPrice in v4 pool", latestClearingPrice);
        emit log_named_decimal_uint("latestCurrencyRaised in v4 pool", latestCurrencyRaised, 18);
        vm.stopBroadcast();
    }
}
