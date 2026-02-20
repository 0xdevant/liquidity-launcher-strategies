// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ProceedsSplitParameters
/// @notice Parameters for the SSLForTokenLBPStrategyBasic contract
struct ProceedsSplitParameters {
    uint24 proceedsSplitMBP; // the percentage of the currency and token during migration that will be split to the proceedsRecipient, expressed in mps (1e7 = 100%)
    address proceedsRecipient;
}
