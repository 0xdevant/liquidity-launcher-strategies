// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IContinuousClearingAuction} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {ILBPStrategyBasic} from "liquidity-launcher/src/interfaces/ILBPStrategyBasic.sol";
import {MigrationData} from "liquidity-launcher/src/types/MigrationData.sol";
import {TickBounds} from "liquidity-launcher/src/types/PositionTypes.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TokenPricing} from "liquidity-launcher/src/libraries/TokenPricing.sol";
import {Helpers} from "script/common/Helpers.sol";
import {SSLForTokenLBPStrategyBasicTestBase} from "test/SSLForTokenLBPStrategyBasicTestBase.t.sol";
import {MockSSLForTokenLBPStrategyBasic} from "test/mocks/MockSSLForTokenLBPStrategyBasic.sol";
import {SSLForTokenLBPStrategyBasicTestHelpers} from "test/helpers/SSLForTokenLBPStrategyBasicTestHelpers.sol";
import {Constants} from "test/Constants.sol";
import {ISSLForTokenLBPStrategyBasic} from "src/interfaces/ISSLForTokenLBPStrategyBasic.sol";

interface ICustomContinuousClearingAuction is IContinuousClearingAuction {
    function clearingPrice() external view returns (uint256);
}

interface INFTPositionManager is IPositionManager, IERC721 {}

contract SSLForTokenLBPStrategyBasicTest is
    SSLForTokenLBPStrategyBasicTestBase,
    SSLForTokenLBPStrategyBasicTestHelpers
{
    using TokenPricing for uint256;

    uint24 public constant MAX_PROCEEDS_SPLIT_MBP = 3e6;

    function test_InitialState_ProceedsSplit() public view {
        assertEq(sslForTokenLBP.PROCEEDS_SPLIT_MBP(), proceedsSplitParams.proceedsSplitMBP);
        assertEq(sslForTokenLBP.PROCEEDS_RECIPIENT(), proceedsSplitParams.proceedsRecipient);
    }

    function test_Constructor_RevertWhenProceedsSplitTooHigh() public {
        proceedsSplitParams.proceedsSplitMBP = 4e6; // 40%
        vm.expectRevert(
            abi.encodeWithSelector(
                ISSLForTokenLBPStrategyBasic.ProceedsSplitTooHigh.selector, 4e6, MAX_PROCEEDS_SPLIT_MBP
            )
        );
        new MockSSLForTokenLBPStrategyBasic(
            address(token),
            _configuration.distributionParams.amount,
            _configuration.migratorParams,
            _configuration.auctionParams,
            IPositionManager(Constants.MAINNET_POSITION_MANAGER),
            IPoolManager(Constants.MAINNET_POOL_MANAGER),
            proceedsSplitParams
        );
    }

    function test_migrate_validateMigration_RevertWhenMigrationNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPStrategyBasic.MigrationNotAllowed.selector, sslForTokenLBP.migrationBlock(), block.number
            )
        );
        sslForTokenLBP.migrate();
    }

    function test_migrate_validateMigration_RevertWhenCurrencyRaisedTooHigh() public {
        vm.roll(sslForTokenLBP.migrationBlock());
        vm.mockCall(
            address(sslForTokenLBP.auction()),
            abi.encodeWithSelector(IContinuousClearingAuction.currencyRaised.selector),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPStrategyBasic.CurrencyAmountTooHigh.selector, type(uint256).max, type(uint128).max
            )
        );
        sslForTokenLBP.migrate();
    }

    function test_migrate_validateMigration_RevertWhenNoCurrencyRaised() public {
        vm.roll(sslForTokenLBP.migrationBlock());
        vm.mockCall(
            address(sslForTokenLBP.auction()),
            abi.encodeWithSelector(IContinuousClearingAuction.currencyRaised.selector),
            abi.encode(0)
        );
        vm.expectRevert(abi.encodeWithSelector(ILBPStrategyBasic.NoCurrencyRaised.selector));
        sslForTokenLBP.migrate();
    }

    function test_migrate_validateMigration_RevertWhenInsufficientCurrency() public {
        vm.roll(sslForTokenLBP.migrationBlock());
        vm.mockCall(
            address(sslForTokenLBP.auction()),
            abi.encodeWithSelector(IContinuousClearingAuction.currencyRaised.selector),
            abi.encode(100e18)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPStrategyBasic.InsufficientCurrency.selector, 100e18, address(sslForTokenLBP).balance
            )
        );
        sslForTokenLBP.migrate();
    }

    function test_migrate_SameBidPerBlock_UntilGraduated_WithLog() public {
        vm.skip(true);
        IContinuousClearingAuction auction = sslForTokenLBP.auction();

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        // NOTE: Change to test different purchase amounts
        uint128 TOKEN_AMOUNT = 350e18;

        uint256 bidId;
        while (!auction.isGraduated()) {
            require(bidId + 1 < auction.endBlock(), "End block reached before auction graduated");

            _submitBid(
                auction,
                alice,
                Helpers.inputAmountForTokens(
                    TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING)
                ), // 500 tokens at floor price + 1 tick
                Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // price
                Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
                bidId
            );
            bidId++;

            // logPriceAndCurrencyRaised(auction);

            vm.roll(auction.startBlock() + bidId); // already + 1
        }

        // Take balance snapshot
        BalanceSnapshot memory before = takeBalanceSnapshot(
            address(token),
            address(0), // ETH
            Constants.MAINNET_POSITION_MANAGER,
            Constants.MAINNET_POOL_MANAGER,
            address(3)
        );

        // move to auction end
        vm.roll(auction.endBlock());

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");
        vm.roll(sslForTokenLBP.migrationBlock());
        sslForTokenLBP.migrate();

        // Take balance snapshot after
        BalanceSnapshot memory afterMigration = takeBalanceSnapshot(
            address(token), address(0), Constants.MAINNET_POSITION_MANAGER, Constants.MAINNET_POOL_MANAGER, address(3)
        );

        // Verify balances
        assertLBPStateAfterMigration(sslForTokenLBP, address(token), address(0));
        assertBalancesAfterMigration(before, afterMigration);

        logPriceAndCurrencyRaised(auction);

        // log the token ids that LP rec
        INFTPositionManager positionManager = INFTPositionManager(Constants.MAINNET_POSITION_MANAGER);
        assertEq(positionManager.ownerOf(nextTokenId), lpRecipient);
        assertEq(positionManager.ownerOf(nextTokenId + 1), lpRecipient);

        // log the currency and token balance of lbp
        emit log_named_decimal_uint("sslForTokenLBP currency balance", address(sslForTokenLBP).balance, 18);
        emit log_named_decimal_uint("sslForTokenLBP token balance", token.balanceOf(address(sslForTokenLBP)), 18);
        // log the currency and token balance of proceedsRecipient
        emit log_named_decimal_uint("proceedsRecipient's currency balance", address(proceedsRecipient).balance, 18);
        emit log_named_decimal_uint("proceedsRecipient's token balance", token.balanceOf(proceedsRecipient), 18);
    }

    function test_migrate_CreatedOneSidedPosition() public {
        IContinuousClearingAuction auction = sslForTokenLBP.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        // logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        // NOTE: Change to test different purchase amounts
        uint128 TOKEN_AMOUNT = 350e18;

        uint256 bidId;
        while (!auction.isGraduated()) {
            require(bidId + 1 < auction.endBlock(), "End block reached before auction graduated");

            _submitBid(
                auction,
                alice,
                Helpers.inputAmountForTokens(
                    TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING)
                ), // 500 tokens at floor price + 1 tick
                Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // price
                Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
                bidId
            );
            bidId++;

            // logPriceAndCurrencyRaised(auction);

            vm.roll(auction.startBlock() + bidId); // already + 1
        }

        // Take balance snapshot
        BalanceSnapshot memory before = takeBalanceSnapshot(
            address(token),
            address(0), // ETH
            Constants.MAINNET_POSITION_MANAGER,
            Constants.MAINNET_POOL_MANAGER,
            address(3)
        );

        // move to auction end
        vm.roll(auction.endBlock());

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        assertEq(proceedsRecipient.balance, 0);
        assertEq(token.balanceOf(proceedsRecipient), 0);

        // 4. Migration to Uniswap V4
        vm.roll(sslForTokenLBP.migrationBlock());
        sslForTokenLBP.migrate();

        // Take balance snapshot after
        BalanceSnapshot memory afterMigration = takeBalanceSnapshot(
            address(token), address(0), Constants.MAINNET_POSITION_MANAGER, Constants.MAINNET_POOL_MANAGER, address(3)
        );

        // Verify balances
        assertLBPStateAfterMigration(sslForTokenLBP, address(token), address(0));
        assertBalancesAfterMigration(before, afterMigration);

        INFTPositionManager positionManager = INFTPositionManager(Constants.MAINNET_POSITION_MANAGER);
        assertEq(positionManager.ownerOf(nextTokenId), lpRecipient);
        assertEq(positionManager.ownerOf(nextTokenId + 1), lpRecipient);
        // single sided position
        assertEq(positionManager.ownerOf(nextTokenId + 2), proceedsRecipient);

        assertGt(proceedsRecipient.balance, 0);
        assertGt(token.balanceOf(proceedsRecipient), 0);
    }

    function test_migrate_NotCreatedOneSidedPosition() public {
        /* use new configuration that does not create one sided position */
        _configuration.migratorParams.createOneSidedTokenPosition = false;
        _configuration.migratorParams.createOneSidedCurrencyPosition = false;

        _configuration.tokenCreationParams.name = "Full Launch Token 2";

        _configureLBP(
            address(sslForTokenLBPStrategyBasicFactory),
            abi.encode(_configuration.migratorParams, _configuration.auctionParams, proceedsSplitParams)
        );
        _createAndDistributeToken(_mineSSLForTokenLBPSalt());
        _useSSLForTokenLBP();

        IContinuousClearingAuction auction = sslForTokenLBP.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        // move to auction start
        vm.roll(auction.startBlock());

        // NOTE: Change to test different purchase amounts
        uint128 TOKEN_AMOUNT = 350e18;

        uint256 bidId;
        while (!auction.isGraduated()) {
            require(bidId + 1 < auction.endBlock(), "End block reached before auction graduated");

            _submitBid(
                auction,
                alice,
                Helpers.inputAmountForTokens(
                    TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING)
                ), // 500 tokens at floor price + 1 tick
                Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // price
                Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
                bidId
            );
            bidId++;

            vm.roll(auction.startBlock() + bidId); // already + 1
        }

        // Take balance snapshot
        BalanceSnapshot memory before = takeBalanceSnapshot(
            address(token),
            address(0), // ETH
            Constants.MAINNET_POSITION_MANAGER,
            Constants.MAINNET_POOL_MANAGER,
            address(3)
        );

        // move to auction end
        vm.roll(auction.endBlock());

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        assertEq(proceedsRecipient.balance, 0);
        assertEq(token.balanceOf(proceedsRecipient), 0);

        // 4. Migration to Uniswap V4
        vm.roll(sslForTokenLBP.migrationBlock());
        sslForTokenLBP.migrate();

        // Take balance snapshot after
        BalanceSnapshot memory afterMigration = takeBalanceSnapshot(
            address(token), address(0), Constants.MAINNET_POSITION_MANAGER, Constants.MAINNET_POOL_MANAGER, address(3)
        );

        // Verify balances
        assertBalancesAfterMigration(before, afterMigration);
        // leftover tokens, no leftover currency
        assertGt(token.balanceOf(address(sslForTokenLBP)), 0);
        assertLe(address(sslForTokenLBP).balance, SSLForTokenLBPStrategyBasicTestHelpers.DUST_AMOUNT); // dust

        uint256 operatorBalanceBefore = token.balanceOf(sslForTokenLBP.operator());

        vm.roll(sslForTokenLBP.sweepBlock());
        vm.prank(sslForTokenLBP.operator());
        sslForTokenLBP.sweepToken();
        assertEq(token.balanceOf(address(sslForTokenLBP)), 0);
        assertGt(token.balanceOf(sslForTokenLBP.operator()), operatorBalanceBefore);

        INFTPositionManager positionManager = INFTPositionManager(Constants.MAINNET_POSITION_MANAGER);
        // original full range position
        assertEq(positionManager.ownerOf(nextTokenId), lpRecipient);
        // withdrawn token minted as a single sided position
        assertEq(positionManager.ownerOf(nextTokenId + 1), proceedsRecipient);

        // Verify one-sided position is not created
        assertPositionNotCreated(positionManager, nextTokenId + 2);

        assertGt(proceedsRecipient.balance, 0);
        assertGt(token.balanceOf(proceedsRecipient), 0);
    }

    function test_withdrawLQAndMintTokenLPAndSendCurrency() public {
        vm.mockCall(
            address(sslForTokenLBP.auction()),
            abi.encodeWithSelector(ICustomContinuousClearingAuction.clearingPrice.selector),
            abi.encode(Constants.SQRT_PRICE_1_1)
        );
        MigrationData memory data = sslForTokenLBP.prepareMigrationData();
        PoolKey memory key = sslForTokenLBP.initializePool(data);
        vm.expectRevert(abi.encodeWithSelector(ISSLForTokenLBPStrategyBasic.TickBoundsAreZero.selector));
        sslForTokenLBP.withdrawLQAndMintTokenLPAndSendCurrency(data, key); // reverts because tick bounds are zero
    }

    function test_getLeftTickBounds_ReturnDefaultZeroBoundsWhenTooCloseToMinTick() public view {
        TickBounds memory bounds =
            sslForTokenLBP.getLeftTickBounds(TickMath.MIN_SQRT_PRICE, _configuration.migratorParams.poolTickSpacing);
        assertEq(bounds.lowerTick, 0);
        assertEq(bounds.upperTick, 0);
    }
}

