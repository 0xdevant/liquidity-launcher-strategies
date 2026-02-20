// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {
    IContinuousClearingAuction
} from "lib/continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";

import {SepoliaConstants, AuctionParameters} from "../common/SepoliaConstants.sol";
import {Helpers} from "../common/Helpers.sol";

contract SubmitBidSepoliaScript is Script, SepoliaConstants {
    using FixedPointMathLib for *;
    using Helpers for IContinuousClearingAuction;

    uint256 public constant BLOCKS_TO_SUBMIT_BIDS = 3;

    // NOTE: change this for every new auction!
    IContinuousClearingAuction public auction = IContinuousClearingAuction(AUCTION);
    AuctionParameters public decodedAuctionParams = abi.decode(configuration.auctionParams, (AuctionParameters));

    function run() public {
        vm.broadcast();
        uint256 startBlock = block.number;
        uint256 untilBlock = startBlock + BLOCKS_TO_SUBMIT_BIDS;

        while (block.number != startBlock + 1 && block.number < untilBlock) {
            vm.sleep(5_000);

            if (block.number != startBlock + 1) {
                continue;
            }

            vm.startBroadcast();
            startBlock = block.number;
            auction.submitBid(
                TEST_ANT_CALLER,
                Helpers.inputAmountForTokens(
                    1e18,
                    Helpers.tickNumberToPriceX96(2, decodedAuctionParams.floorPrice, decodedAuctionParams.tickSpacing)
                ), // 1 tokens at floor price + 1 tick
                Helpers.tickNumberToPriceX96(2, decodedAuctionParams.floorPrice, decodedAuctionParams.tickSpacing), // price
                Helpers.tickNumberToPriceX96(1, decodedAuctionParams.floorPrice, decodedAuctionParams.tickSpacing) // prev price (floor price)
            );
            vm.stopBroadcast();

            console.log("current block number:", startBlock);
            // console.log("bidId:", bidId);
        }
    }
}
