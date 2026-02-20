// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {
    IContinuousClearingAuction
} from "lib/continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {ICheckpointStorage} from "continuous-clearing-auction/src/interfaces/ICheckpointStorage.sol";

import {TenderlyConstants, AuctionParameters} from "../common/TenderlyConstants.sol";
import {Helpers} from "../common/Helpers.sol";

interface ILBPStrategyBasic {
    function migrate() external;

    function migrationBlock() external view returns (uint64);
}

contract SubmitBidTenderlyScript is Script, TenderlyConstants {
    using FixedPointMathLib for *;
    using Helpers for IContinuousClearingAuction;

    uint256 public constant BLOCKS_TO_SUBMIT_BIDS = 3;

    // NOTE: change AUCTION & LBP_STRATEGY_BASIC for every new auction!
    IContinuousClearingAuction public auction = IContinuousClearingAuction(AUCTION);
    ILBPStrategyBasic public lbp = ILBPStrategyBasic(LBP_STRATEGY_BASIC);

    function run() public {
        // vm.broadcast();
        // uint256 untilBlock = startBlock + BLOCKS_TO_SUBMIT_BIDS;

        AuctionParameters memory params = Helpers.getAuctionParams(configuration.auctionParams);
        uint256 bidNumber = 0;
        uint128 BUY_TOKEN_AMOUNT = 10000e18;

        for (uint256 i = 0; i < BLOCKS_TO_SUBMIT_BIDS; i++) {
            vm.startBroadcast();
            // need check how to check latest states due to state changes delay
            // while (!auction.isGraduated()) {
            require(block.number < auction.endBlock(), "End block reached before auction graduated");
            console.log("---- Submitting Bid %s ----", bidNumber);

            // uint256 startBlock = block.number;
            // bytes memory result = vm.rpc("evm_increaseBlocks", "[\"0x1\"]");
            // require(block.number == startBlock + 1, "Block number not increased");

            auction.submitBid(
                TEST_ANT_CALLER,
                Helpers.inputAmountForTokens(
                    BUY_TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2 + i, params.floorPrice, params.tickSpacing)
                ), // buy tokens at floor price + 1 tick
                Helpers.tickNumberToPriceX96(2 + i, params.floorPrice, params.tickSpacing), // price
                Helpers.tickNumberToPriceX96(1, params.floorPrice, params.tickSpacing) // prev price (floor price)
            );
            bidNumber++;

            auction.checkpoint();

            // can't print the updated states on Tenderly due to state changes delay
            // uint256 clearingPrice = ICheckpointStorage(address(auction)).clearingPrice();
            // uint256 currencyRaised = auction.currencyRaised();

            // emit log_named_uint("Current clearingPrice in Q96", clearingPrice);
            // emit log_named_decimal_uint("Current currencyRaised", currencyRaised, 18);

            // emit log_string("\n");
            vm.stopBroadcast();
        }
    }
}
