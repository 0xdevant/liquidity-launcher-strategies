// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IDistributionStrategy} from "liquidity-launcher/src/interfaces/IDistributionStrategy.sol";
import {IDistributionContract} from "liquidity-launcher/src/interfaces/IDistributionContract.sol";

interface ICustomAllocationStrategy is IDistributionStrategy, IDistributionContract {
    /// @notice Error thrown when the caller is not the LiquidityLauncher
    error OnlyLiquidityLauncher();

    /// @notice Error thrown when the recipient is the zero address
    error InvalidRecipient();

    /// @notice Error thrown when the allocation split is too high
    /// @param allocationAmount The invalid allocation amount
    /// @param maxAllocationAmount The maximum allocation amount
    error AllocationSplitTooHigh(uint256 allocationAmount, uint256 maxAllocationAmount);

    /// @notice Emitted when the tokens are allocated to the allocation recipient
    /// @param recipient The address of the allocation recipient
    /// @param amount The amount of tokens allocated
    event TokensAllocated(address indexed token, address recipient, uint256 amount);

    /// @notice Parameters struct to be used by the CustomAllocationStrategy during `onTokensReceived`
    struct Parameters {
        /// @notice The token that is being distributed
        address tokenAddress;
        /// @notice The address that will receive the allocation
        address allocationRecipient;
        /// @notice The amount of tokens allocated to the allocation recipient
        uint256 allocationAmount;
    }
}
