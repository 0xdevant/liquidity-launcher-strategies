// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
// `getAmountsForLiquidity` available in v4-core test utils only
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {MigratorParameters} from "liquidity-launcher/src/types/MigratorParameters.sol";
import {MigrationData} from "liquidity-launcher/src/types/MigrationData.sol";
import {BasePositionParams} from "liquidity-launcher/src/types/PositionTypes.sol";
import {ParamsBuilder} from "liquidity-launcher/src/libraries/ParamsBuilder.sol";
import {TickCalculations} from "liquidity-launcher/src/libraries/TickCalculations.sol";
import {TickBounds} from "liquidity-launcher/src/types/PositionTypes.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {BaseLBPStrategyBasic} from "./BaseLBPStrategyBasic.sol";
import {ProceedsSplitParameters} from "./types/ProceedsSplitParameters.sol";
import {ISSLForTokenLBPStrategyBasic} from "./interfaces/ISSLForTokenLBPStrategyBasic.sol";

/// @title SSLForTokenLBPStrategyBasic
/// @notice Custom Strategy built on top of LBPStrategyBasic to customize usage of the migration liquidity.
/// Part of the migration liquidity will be withdrawn, the currency portion will be sent to `PROCEEDS_RECIPIENT` directly
/// while the token portion will be minted as a single sided position to `PROCEEDS_RECIPIENT`.
contract SSLForTokenLBPStrategyBasic is BaseLBPStrategyBasic, ISSLForTokenLBPStrategyBasic {
    using TickCalculations for int24;

    /// @notice Maximum value for 100% in Milli-Basis Points
    uint24 public constant MAX_MBP = 1e7;
    /// @notice The maximum proceeds split percentage represented in MBP (1e7 = 100%)
    /// @dev This will be split equally between the currency and token
    uint24 public constant MAX_PROCEEDS_SPLIT_MBP = 3e6;

    uint24 public immutable PROCEEDS_SPLIT_MBP;
    address public immutable PROCEEDS_RECIPIENT;

    constructor(
        address _token,
        uint128 _totalSupply,
        MigratorParameters memory _migratorParams,
        bytes memory _auctionParams,
        IPositionManager _positionManager,
        IPoolManager _poolManager,
        ProceedsSplitParameters memory _proceedsSplitParams
    ) BaseLBPStrategyBasic(_token, _totalSupply, _migratorParams, _auctionParams, _positionManager, _poolManager) {
        require(
            _proceedsSplitParams.proceedsSplitMBP <= MAX_PROCEEDS_SPLIT_MBP,
            ProceedsSplitTooHigh(_proceedsSplitParams.proceedsSplitMBP, MAX_PROCEEDS_SPLIT_MBP)
        );
        PROCEEDS_SPLIT_MBP = _proceedsSplitParams.proceedsSplitMBP;
        PROCEEDS_RECIPIENT = _proceedsSplitParams.proceedsRecipient;
    }

    /// @inheritdoc BaseLBPStrategyBasic
    function migrate() external override {
        (MigrationData memory data, PoolKey memory key) = _migrate();

        /* Withdraw part of the migration liquidity -> mint single sided position with the token portion -> send the currency portion to `proceedsRecipient` */
        // Full range position is initially sent to this contract to handle proceeds distribution and then sent back to `positionRecipient`
        uint256 tokenId = _withdrawLQAndMintTokenLPAndSendCurrency(data, key);

        // transfer the full range position back to positionRecipient
        IERC721(address(positionManager)).transferFrom(address(this), positionRecipient, tokenId);
    }

    /// @dev Implementation of `migrate` from LBPStrategyBasic
    function _migrate() internal returns (MigrationData memory data, PoolKey memory key) {
        _validateMigration();

        data = _prepareMigrationData();
        key = _initializePool(data);

        bytes memory plan = _createPositionPlan(data);
        _transferAssetsAndExecutePlan(data, plan);

        emit Migrated(key, data.sqrtPriceX96);
    }

    /// @notice Creates the position plan based on migration data
    /// @param data Migration data with all necessary parameters
    /// @return plan The encoded position plan
    function _createPositionPlan(MigrationData memory data) internal view override returns (bytes memory plan) {
        bytes memory actions;
        bytes[] memory params;

        address poolToken = getPoolToken();

        // Create base parameters
        BasePositionParams memory baseParams = BasePositionParams({
            currency: currency,
            poolToken: poolToken,
            poolLPFee: poolLPFee,
            poolTickSpacing: poolTickSpacing,
            initialSqrtPriceX96: data.sqrtPriceX96,
            liquidity: data.liquidity,
            // positionRecipient is set to this contract in order to handle proceeds distribution
            positionRecipient: address(this),
            hooks: IHooks(address(this))
        });

        if (data.shouldCreateOneSided) {
            (actions, params) = _createFullRangePositionPlan(
                baseParams,
                data.initialTokenAmount,
                data.initialCurrencyAmount,
                ParamsBuilder.FULL_RANGE_WITH_ONE_SIDED_SIZE
            );
            // one sided position can still be sent to positionRecipient and doesn't affect `_createFinalTakePairPlan`
            baseParams.positionRecipient = positionRecipient;
            (actions, params) = _createOneSidedPositionPlan(
                baseParams, actions, params, data.initialTokenAmount, data.leftoverCurrency
            );
            data.hasOneSidedParams = params.length == ParamsBuilder.FULL_RANGE_WITH_ONE_SIDED_SIZE;
        } else {
            (actions, params) = _createFullRangePositionPlan(
                baseParams, data.initialTokenAmount, data.initialCurrencyAmount, ParamsBuilder.FULL_RANGE_SIZE
            );
        }

        (actions, params) = _createFinalTakePairPlan(baseParams, actions, params);

        return abi.encode(actions, params);
    }

    /// @notice Withdraws part of the migration liquidity, mints a single sided position with the token portion
    /// and sends the currency portion to `PROCEEDS_RECIPIENT`
    /// @param data Migration data with all necessary parameters
    /// @param key The pool key
    /// @return tokenId The token id of the original full range position
    function _withdrawLQAndMintTokenLPAndSendCurrency(MigrationData memory data, PoolKey memory key)
        internal
        returns (uint256 tokenId)
    {
        /* checking for minting token single sided position */
        // Get tick bounds based on position side (left side for token single sided position)
        TickBounds memory bounds = _getLeftSideBounds(data.sqrtPriceX96, poolTickSpacing);
        bool isTickBoundsNotZero = bounds.lowerTick != 0 && bounds.upperTick != 0;
        require(isTickBoundsNotZero, TickBoundsAreZero());

        uint128 splitCurrencyAmount = data.initialCurrencyAmount * PROCEEDS_SPLIT_MBP / 2 / MAX_MBP;
        uint128 splitTokenAmount = data.initialTokenAmount * PROCEEDS_SPLIT_MBP / 2 / MAX_MBP;
        bool isTokenCurrency0 = currency < token ? false : true;

        uint128 withdrawingLQ = LiquidityAmounts.getLiquidityForAmounts(
            data.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(poolTickSpacing)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(poolTickSpacing)),
            isTokenCurrency0 ? splitTokenAmount : splitCurrencyAmount,
            isTokenCurrency0 ? splitCurrencyAmount : splitTokenAmount
        );
        (uint256 lqToCurrencyAmount, uint256 lqToTokenAmount) = LiquidityAmounts.getAmountsForLiquidity(
            data.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(poolTickSpacing)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(poolTickSpacing)),
            withdrawingLQ
        );

        /* checking for minting token single sided position */
        // If this overflows, the transaction will revert and no position will be created
        uint128 mintingTokenLQ = LiquidityAmounts.getLiquidityForAmounts(
            data.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(bounds.lowerTick),
            TickMath.getSqrtPriceAtTick(bounds.upperTick),
            0,
            lqToTokenAmount
        );
        bool isMintingTokenLQValid = mintingTokenLQ != 0
            && data.liquidity + mintingTokenLQ <= poolTickSpacing.tickSpacingToMaxLiquidityPerTick();
        require(isMintingTokenLQValid, InvalidNewLiquidity(mintingTokenLQ));

        bool mintedSingleSided = data.shouldCreateOneSided && isTickBoundsNotZero && isMintingTokenLQValid;

        // right after minting the LP(s) from `migrate`, calculate the token id of the full range position while accounting for possible single sided position
        // `shouldCreateOneSided` is finalized at this point so it's either minus 2 if minted single sided position or minus 1 if only minted full range position
        tokenId = mintedSingleSided ? positionManager.nextTokenId() - 2 : positionManager.nextTokenId() - 1;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](4);
        // 0 for amountMin is safe here since it's right after `migrate` and these operations are atomic
        params[0] = abi.encode(tokenId, withdrawingLQ, 0, 0, new bytes(0));
        params[1] = abi.encode(
            key,
            bounds.lowerTick,
            bounds.upperTick,
            mintingTokenLQ,
            0,
            lqToTokenAmount,
            PROCEEDS_RECIPIENT,
            new bytes(0)
        );
        params[2] = abi.encode(key.currency1, ActionConstants.CONTRACT_BALANCE, false);
        // take withdrawn currency and leftover dust token to proceeds recipient
        params[3] = abi.encode(key.currency0, key.currency1, PROCEEDS_RECIPIENT);

        bytes memory withdrawAndMintSingleSidedPositionPlan = abi.encode(actions, params);
        positionManager.modifyLiquidities(withdrawAndMintSingleSidedPositionPlan, block.timestamp + 1);

        emit LQWithdrawnAndMintedTokenLPAndSentCurrency(tokenId, lqToCurrencyAmount, lqToTokenAmount);
    }

    /// @notice Gets tick bounds for a left-side position (below current tick)
    /// @param initialSqrtPriceX96 The initial sqrt price of the position
    /// @param tickSpacing The tick spacing of the pool
    /// @return bounds The tick bounds for the left-side position (returns 0,0 if the current tick is too close to MIN_TICK)
    function _getLeftSideBounds(uint160 initialSqrtPriceX96, int24 tickSpacing)
        internal
        pure
        returns (TickBounds memory bounds)
    {
        int24 initialTick = TickMath.getTickAtSqrtPrice(initialSqrtPriceX96);

        // Check if position is too close to MIN_TICK. If so, return a lower tick and upper tick of 0
        if (initialTick - TickMath.MIN_TICK < tickSpacing) {
            return bounds;
        }

        bounds = TickBounds({
            lowerTick: TickMath.minUsableTick(tickSpacing), // Rounds to the nearest multiple of tick spacing (rounds towards 0 since MIN_TICK is negative)
            upperTick: initialTick.tickFloor(tickSpacing) // Rounds to the nearest multiple of tick spacing if needed (rounds toward -infinity)
        });

        return bounds;
    }
}
