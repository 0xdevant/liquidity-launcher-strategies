// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {
    IContinuousClearingAuction,
    AuctionParameters
} from "lib/continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";

library Helpers {
    using FixedPointMathLib for *;

    function inputAmountForTokens(uint128 tokens, uint256 maxPrice) internal pure returns (uint128) {
        // `floor(x * y / d)` with full precision, rounded up
        return uint128(tokens.fullMulDivUp(maxPrice, FixedPoint96.Q96));
    }

    function tickNumberToPriceX96(uint256 tickNumber, uint256 floorPrice, uint256 tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return floorPrice + (tickNumber - 1) * tickSpacing;
    }

    function getAuctionParams(bytes memory params) internal pure returns (AuctionParameters memory) {
        return abi.decode(params, (AuctionParameters));
    }

    function submitBid(
        IContinuousClearingAuction auction,
        address bidder,
        uint128 tokenAmount,
        uint256 priceX96,
        uint256 prevPriceX96
    ) internal returns (uint256) {
        uint128 inputAmount = tokenAmount;

        uint256 bidId = auction.submitBid{gas: 1_000_000, value: inputAmount}(
            priceX96, // maxPrice
            inputAmount, // amount
            bidder, // owner
            prevPriceX96, // prevTickPrice hint
            bytes("") // hookData
        );

        return bidId;
    }
}
