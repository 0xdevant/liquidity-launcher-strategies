// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MigrationData} from "liquidity-launcher/src/types/MigrationData.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickBounds} from "liquidity-launcher/src/types/PositionTypes.sol";

import {MigratorParameters} from "script/common/Types.sol";
import {ProceedsSplitParameters} from "src/types/ProceedsSplitParameters.sol";
import {SSLForTokenLBPStrategyBasic} from "src/SSLForTokenLBPStrategyBasic.sol";

contract SSLForTokenLBPStrategyBasicHarness is SSLForTokenLBPStrategyBasic {
    constructor(
        address _token,
        uint128 _totalSupply,
        MigratorParameters memory _migratorParams,
        bytes memory _auctionParams,
        IPositionManager _positionManager,
        IPoolManager _poolManager,
        ProceedsSplitParameters memory _proceedsSplitParams
    )
        SSLForTokenLBPStrategyBasic(
            _token, _totalSupply, _migratorParams, _auctionParams, _positionManager, _poolManager, _proceedsSplitParams
        )
    {}

    function withdrawLQAndMintTokenLPAndSendCurrency(MigrationData memory data, PoolKey memory key)
        public
        returns (uint256 tokenId)
    {
        tokenId = _withdrawLQAndMintTokenLPAndSendCurrency(data, key);
    }

    function prepareMigrationData() public view returns (MigrationData memory data) {
        data = _prepareMigrationData();
    }

    function initializePool(MigrationData memory data) public returns (PoolKey memory key) {
        key = _initializePool(data);
    }

    function getLeftTickBounds(uint160 initialSqrtPriceX96, int24 tickSpacing)
        public
        pure
        returns (TickBounds memory bounds)
    {
        bounds = _getLeftSideBounds(initialSqrtPriceX96, tickSpacing);
    }
}
