// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {MigratorParameters} from "liquidity-launcher/src/types/MigratorParameters.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SSLForTokenLBPStrategyBasic} from "src/SSLForTokenLBPStrategyBasic.sol";
import {ProceedsSplitParameters} from "src/types/ProceedsSplitParameters.sol";

/// @title MockSSLForTokenLBPStrategyBasic
/// @notice Test version of SSLForTokenLBPStrategyBasic that skips hook address validation
contract MockSSLForTokenLBPStrategyBasic is SSLForTokenLBPStrategyBasic {
    constructor(
        address _tokenAddress,
        uint128 _totalSupply,
        MigratorParameters memory migratorParams,
        bytes memory auctionParams,
        IPositionManager _positionManager,
        IPoolManager _poolManager,
        ProceedsSplitParameters memory proceedsSplitParams
    )
        SSLForTokenLBPStrategyBasic(
            _tokenAddress,
            _totalSupply,
            migratorParams,
            auctionParams,
            _positionManager,
            _poolManager,
            proceedsSplitParams
        )
    {}

    /// @dev Override to skip hook address validation during testing
    function validateHookAddress(BaseHook) internal pure override {}
}
