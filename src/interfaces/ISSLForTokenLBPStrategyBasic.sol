// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title ISSLForTokenLBPStrategyBasic
/// @notice Interface for the SSLForTokenLBPStrategyBasic contract
interface ISSLForTokenLBPStrategyBasic {
    /// @notice Error thrown when the proceeds split is too high
    /// @param proceedsSplit The invalid proceeds split percentage
    /// @param maxProceedsSplit The maximum proceeds split percentage
    error ProceedsSplitTooHigh(uint24 proceedsSplit, uint24 maxProceedsSplit);

    /// @notice Error thrown when the tick bounds are 0,0 (which means the current tick is too close to MIN_TICK or MAX_TICK)
    error TickBoundsAreZero();

    /// @notice Error thrown when the new liquidity is zero or overflows
    /// @param newLiquidity The invalid new liquidity
    error InvalidNewLiquidity(uint128 newLiquidity);

    /// @notice Emitted when part of the liquidity is withdrawn, the tokens are minted as a single sided position to `PROCEEDS_RECIPIENT` and the currency is sent to `PROCEEDS_RECIPIENT`
    /// @param tokenId The token id of the original full range position
    /// @param liquidityToCurrencyAmount The amount of currency that is withdrawn to be sent to proceeds recipient
    /// @param liquidityToTokenAmount The amount of token that is withdrawn to be minted as a single sided position
    event LQWithdrawnAndMintedTokenLPAndSentCurrency(
        uint256 tokenId, uint256 liquidityToCurrencyAmount, uint256 liquidityToTokenAmount
    );
}
