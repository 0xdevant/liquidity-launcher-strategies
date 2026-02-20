// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {
    IContinuousClearingAuction,
    AuctionParameters
} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {MaxBidPriceLib} from "continuous-clearing-auction/src/libraries/MaxBidPriceLib.sol";
import {Checkpoint, ValueX7} from "continuous-clearing-auction/src/libraries/CheckpointLib.sol";
import {ICheckpointStorage} from "continuous-clearing-auction/src/interfaces/ICheckpointStorage.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {LBPStrategyBasicFactory} from "liquidity-launcher/src/distributionStrategies/LBPStrategyBasicFactory.sol";
import {LBPStrategyBasic} from "liquidity-launcher/src/distributionContracts/LBPStrategyBasic.sol";
import {LBPTestHelpers} from "liquidity-launcher/test/distributionContracts/helpers/LBPTestHelpers.sol";

import {MigratorParameters, Distribution} from "script/common/Types.sol";
import {Helpers} from "script/common/Helpers.sol";
import {Log} from "script/common/Log.sol";
import {Constants} from "../Constants.sol";
import {ILBPStrategyBasicView} from "../ILBPStrategyBasicView.sol";
import {FullLaunchTestBase} from "../FullLaunchTestBase.t.sol";

contract FullLaunchTest is FullLaunchTestBase, Log, LBPTestHelpers {
    using FixedPointMathLib for *;
    using AuctionStepsBuilder for bytes;

    LBPStrategyBasicFactory lbpStrategyBasicFactory;
    LBPStrategyBasic lbp;

    function setUp() public override {
        super.setUp();

        // AuctionParameters memory auctionParams = abi.decode(_configuration.auctionParams, (AuctionParameters));
        // console2.log("startBlock", auctionParams.startBlock);
        // console2.log("endBlock", auctionParams.endBlock);

        _replaceToSimulationConfig();

        lbpStrategyBasicFactory = new LBPStrategyBasicFactory(
            IPositionManager(Constants.MAINNET_POSITION_MANAGER), IPoolManager(Constants.MAINNET_POOL_MANAGER)
        );

        _configureLBP(
            address(lbpStrategyBasicFactory), abi.encode(_configuration.migratorParams, _configuration.auctionParams)
        );
        // 1. (createToken if `shouldCreateToken` is true) + distributeToken
        _createAndDistributeToken(_mineDefaultLBPSalt());
        _useDefaultLBP();
    }

    function test_full_launch_OneBidAndMoveToAuctionEnd() public {
        // vm.skip(true);

        // 2. Auction Phase
        emit log_string("\n------------- Auction Phase -------------");
        IContinuousClearingAuction auction = lbp.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        uint256 BID_ID = 0;

        _submitBid(
            auction,
            alice,
            Helpers.inputAmountForTokens(
                500e18, Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING)
            ), // 500 tokens at floor price + 1 tick
            Helpers.tickNumberToPriceX96(2, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // price
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            BID_ID
        );

        // move to auction end
        vm.roll(auction.endBlock());

        logPriceAndCurrencyRaised(auction);

        assertFalse(auction.isGraduated());
    }

    function test_full_launch_SameBidPerBlock_UntilGraduated() public {
        // 2. Auction Phase
        emit log_string("\n------------- Auction Phase -------------");
        IContinuousClearingAuction auction = lbp.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        // NOTE: Change to test different purchase amounts
        uint128 TOKEN_AMOUNT = 500e18;

        uint256 bidId;
        while (!auction.isGraduated()) {
            require(bidId + 1 < auction.endBlock(), "End block reached before auction graduated");

            console2.log("---- Submitting Bid %s ----", bidId);
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

            logPriceAndCurrencyRaised(auction);

            vm.roll(auction.startBlock() + bidId); // already + 1
            emit log_string("\n");
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

        emit log_string("\n------------- Example of Alice exiting bid and claiming tokens -------------");
        vm.roll(auction.claimBlock());
        uint256 aliceBidId = 0;
        auction.exitBid(aliceBidId);
        vm.prank(alice);
        auction.claimTokens(aliceBidId);

        emit log_named_decimal_uint("alice's tokens", token.balanceOf(alice), 18);
        emit log_named_decimal_uint("auction's tokens", token.balanceOf(address(auction)), 18);

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");
        vm.roll(lbp.migrationBlock());
        lbp.migrate();

        // Take balance snapshot after
        BalanceSnapshot memory afterMigration = takeBalanceSnapshot(
            address(token), address(0), Constants.MAINNET_POSITION_MANAGER, Constants.MAINNET_POOL_MANAGER, address(3)
        );

        // Verify balances
        assertLBPStateAfterMigration(lbp, address(token), address(0));
        assertBalancesAfterMigration(before, afterMigration);

        logPriceAndCurrencyRaised(auction);
    }

    function test_full_launch_MarketOrderWithMaxCurrencyFromOneBid() public {
        // vm.skip(true);

        // 2. Auction Phase
        emit log_string("\n------------- Auction Phase -------------");
        IContinuousClearingAuction auction = lbp.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        AuctionParameters memory auctionParams = abi.decode(_configuration.auctionParams, (AuctionParameters));
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(auction.totalSupply());
        maxBidPrice = maxBidPrice - maxBidPrice % auctionParams.tickSpacing;
        uint128 currencyNeededToBuyAllSupplyBasedOnFloorPrice =
            uint128(auctionParams.floorPrice * auction.totalSupply() / FixedPoint96.Q96); // 250000 ETH
        uint256 bidId = 0;

        emit log_named_decimal_uint(
            "currencyNeededToBuyAllSupplyBasedOnFloorPrice", currencyNeededToBuyAllSupplyBasedOnFloorPrice, 18
        );

        emit log_string("\n------------- Bidding Phase -------------");
        // alice places max bid market order
        _submitBid(
            auction,
            alice,
            currencyNeededToBuyAllSupplyBasedOnFloorPrice,
            maxBidPrice,
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            bidId
        );

        // move to auction end
        vm.roll(auction.endBlock());

        logPriceAndCurrencyRaised(auction);

        emit log_string("\n------------- Example of claiming tokens after auction end -------------");
        vm.roll(auction.claimBlock());
        auction.exitBid(bidId);
        vm.prank(alice);
        auction.claimTokens(bidId);

        emit log_named_decimal_uint("alice's tokens", token.balanceOf(alice), 18);
        emit log_named_decimal_uint("auction's tokens", token.balanceOf(address(auction)), 18);

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");
        vm.roll(lbp.migrationBlock());
        lbp.migrate();

        logPriceAndCurrencyRaised(auction);
    }

    function test_full_launch_MarketOrderWithMaxCurrencyFromTwoBids() public {
        // vm.skip(true);

        // 2. Auction Phase
        emit log_string("\n------------- Auction Phase -------------");
        IContinuousClearingAuction auction = lbp.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        AuctionParameters memory auctionParams = abi.decode(_configuration.auctionParams, (AuctionParameters));
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(auction.totalSupply());
        maxBidPrice = maxBidPrice - maxBidPrice % auctionParams.tickSpacing;
        uint128 currencyNeededToBuyAllSupplyBasedOnFloorPrice =
            uint128(auctionParams.floorPrice * auction.totalSupply() / FixedPoint96.Q96); // 250000 ETH
        uint256 bidId = 0;

        emit log_named_decimal_uint(
            "currencyNeededToBuyAllSupplyBasedOnFloorPrice", currencyNeededToBuyAllSupplyBasedOnFloorPrice, 18
        );

        emit log_string("\n------------- Bidding Phase -------------");
        // alice places max bid
        _submitBid(
            auction,
            alice,
            currencyNeededToBuyAllSupplyBasedOnFloorPrice,
            maxBidPrice,
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            bidId
        );

        vm.roll(auction.startBlock() + 1);

        // bob places max bid in the next block
        _submitBid(
            auction,
            bob,
            currencyNeededToBuyAllSupplyBasedOnFloorPrice,
            maxBidPrice,
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            bidId + 1
        );

        // move to auction end
        vm.roll(auction.endBlock());

        logPriceAndCurrencyRaised(auction);

        emit log_string("\n------------- Example of claiming tokens after auction end -------------");
        vm.roll(auction.claimBlock());

        auction.exitBid(bidId);
        vm.prank(alice);
        auction.claimTokens(bidId);

        auction.exitBid(bidId + 1);
        vm.prank(bob);
        auction.claimTokens(bidId + 1);

        emit log_named_decimal_uint("alice's tokens", token.balanceOf(alice), 18);
        emit log_named_decimal_uint("bob's tokens", token.balanceOf(bob), 18);
        emit log_named_decimal_uint("auction's tokens", token.balanceOf(address(auction)), 18);

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");
        vm.roll(lbp.migrationBlock());
        lbp.migrate();

        logPriceAndCurrencyRaised(auction);
    }

    function test_full_launch_OneMarketOrderWithMaxCurrency_OneCappedOrderWithMaxCurrency() public {
        // vm.skip(true);

        // 2. Auction Phase
        emit log_string("\n------------- Auction Phase -------------");
        IContinuousClearingAuction auction = lbp.auction();
        assertEq(auction.totalSupply(), _configuration.distributionParams.amount / 2);

        logAuctionConfigs(auction, _configuration.auctionParams);

        // move to auction start
        vm.roll(auction.startBlock());

        AuctionParameters memory auctionParams = abi.decode(_configuration.auctionParams, (AuctionParameters));
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(auction.totalSupply());
        maxBidPrice = maxBidPrice - maxBidPrice % auctionParams.tickSpacing;
        uint128 currencyNeededToBuyAllSupplyBasedOnFloorPrice =
            uint128(auctionParams.floorPrice * auction.totalSupply() / FixedPoint96.Q96); // 250000 ETH
        uint256 bidId = 0;

        emit log_named_decimal_uint(
            "currencyNeededToBuyAllSupplyBasedOnFloorPrice", currencyNeededToBuyAllSupplyBasedOnFloorPrice, 18
        );

        emit log_string("\n------------- Bidding Phase -------------");
        // alice places max bid market order
        _submitBid(
            auction,
            alice,
            uint128(currencyNeededToBuyAllSupplyBasedOnFloorPrice),
            maxBidPrice,
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            bidId
        );

        // bob places max bid capped order
        _submitBid(
            auction,
            bob,
            currencyNeededToBuyAllSupplyBasedOnFloorPrice,
            Helpers.tickNumberToPriceX96(100, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // capped price at tick 100
            Helpers.tickNumberToPriceX96(1, Constants.FLOOR_PRICE, Constants.TICK_SPACING), // prev price (floor price)
            bidId + 1
        );

        // move to auction end
        vm.roll(auction.endBlock());

        logPriceAndCurrencyRaised(auction);

        emit log_string("\n------------- Example of claiming tokens after auction end -------------");
        vm.roll(auction.claimBlock());

        auction.exitBid(bidId);
        vm.prank(alice);
        auction.claimTokens(bidId);

        auction.exitBid(bidId + 1);
        vm.prank(bob);
        auction.claimTokens(bidId + 1);

        emit log_named_decimal_uint("alice's tokens", token.balanceOf(alice), 18);
        emit log_named_decimal_uint("bob's tokens", token.balanceOf(bob), 18);
        emit log_named_decimal_uint("auction's tokens", token.balanceOf(address(auction)), 18);

        assertTrue(auction.isGraduated());
        // 3. Once the auction graduates, it transfers the raised funds to the LBP Strategy and the strategy grabs the final clearing price.
        auction.sweepCurrency();

        // 4. Migration to Uniswap V4
        emit log_string("\n------------- Migration to Uniswap V4 -------------");
        vm.roll(lbp.migrationBlock());
        lbp.migrate();

        logPriceAndCurrencyRaised(auction);
    }

    function _mineDefaultLBPSalt() internal view returns (bytes32 minedSalt) {
        address tokenAddress;

        tokenAddress = shouldCreateToken
            ? computeUERC20Address(
                _configuration.tokenCreationParams.name,
                _configuration.tokenCreationParams.symbol,
                address(liquidityLauncher)
            )
            : Constants.TEST_TOKEN_ADDRESS;

        bytes memory encodedConstructorArgs = abi.encode(
            tokenAddress,
            uint128(_configuration.distributionParams.amount),
            _configuration.migratorParams,
            _configuration.auctionParams,
            IPositionManager(Constants.MAINNET_POSITION_MANAGER),
            IPoolManager(Constants.MAINNET_POOL_MANAGER)
        );
        (, minedSalt) = mine(
            address(liquidityLauncher),
            shouldCreateToken ? address(this) : projectTokenOwner,
            address(lbpStrategyBasicFactory),
            Constants.FLAGS,
            type(LBPStrategyBasic).creationCode,
            encodedConstructorArgs
        );
    }

    function _useDefaultLBP() internal {
        require(address(token) != address(0), "Token not deployed");

        bytes32 saltPassedFromLiquidityLauncher = shouldCreateToken
            ? keccak256(abi.encode(address(this), finalSalt))
            : keccak256(abi.encode(projectTokenOwner, finalSalt));

        lbp = LBPStrategyBasic(
            payable(lbpStrategyBasicFactory.getLBPAddress(
                    address(token),
                    _configuration.distributionParams.amount,
                    _configuration.distributionParams.configData,
                    saltPassedFromLiquidityLauncher,
                    address(liquidityLauncher)
                ))
        );
        _verifyLBPInitialState(ILBPStrategyBasicView(address(lbp)));
        assertEq(lbp.totalSupply(), Constants.DEFAULT_DISTRIBUTION_AMOUNT);
        assertEq(
            lbp.reserveSupply(),
            Constants.DEFAULT_DISTRIBUTION_AMOUNT - _configuration.distributionParams.amount
                * _configuration.migratorParams.tokenSplitToAuction / 1e7
        );
    }

    function _replaceToSimulationConfig() internal {
        require(address(auctionFactory) != address(0), "Auction factory not deployed");
        uint64 blockNumber = uint64(vm.getBlockNumber());

        // NOTE: input your sim configuration here
        _configuration = Configuration({
            tokenCreationParams: TokenCreationParams({
                name: "Full Launch Token",
                symbol: "FLT",
                initialSupply: Constants.DEFAULT_TOTAL_SUPPLY,
                recipient: address(this),
                description: "Full launch token",
                website: "https://test.com",
                image: "https://test.com/image.png"
            }),
            auctionParams: abi.encode(
                AuctionParameters({
                    currency: address(0), // ETH
                    tokensRecipient: leftoverTokensRecipient, // Some valid address
                    fundsRecipient: address(1), // 1 means MSG_SENDER in ActionConstants.sol
                    startBlock: blockNumber,
                    endBlock: blockNumber + 100,
                    claimBlock: blockNumber + 100 + 10,
                    tickSpacing: (1 << FixedPoint96.RESOLUTION) / 2_000,
                    validationHook: address(0), // No validation hook
                    floorPrice: (1 << FixedPoint96.RESOLUTION) / 2_000, // 0.0005 ETH per token
                    requiredCurrencyRaised: 30e18, // 30 ETH
                    // 1000 mps = 1 basis point so 100e3 = 100 basis points i.e. 1% of supply per block
                    auctionStepsData: AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50)
                })
            ),
            migratorParams: MigratorParameters({
                migrationBlock: blockNumber + 500,
                currency: address(0),
                poolLPFee: 500,
                poolTickSpacing: 1,
                tokenSplitToAuction: 5e6,
                // NOTE: this should not be address(0)
                auctionFactory: address(auctionFactory),
                positionRecipient: lpRecipient,
                sweepBlock: blockNumber + 1000,
                operator: testOperator,
                createOneSidedTokenPosition: true,
                createOneSidedCurrencyPosition: true
            }),
            distributionParams: Distribution({
                // configData is empty since we already passed the migratorParams and auctionParams to LBPStrategyBasic
                strategy: address(0),
                amount: Constants.DEFAULT_DISTRIBUTION_AMOUNT,
                configData: ""
            })
        });
    }

    // function assertPositionCreated(
    //     IPositionManager positionManager,
    //     uint256 tokenId,
    //     address expectedCurrency0,
    //     address expectedCurrency1,
    //     uint24 expectedFee,
    //     int24 expectedTickSpacing,
    //     int24 expectedTickLower,
    //     int24 expectedTickUpper
    // ) internal view {
    //     (PoolKey memory poolKey, PositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);

    //     vm.assertEq(Currency.unwrap(poolKey.currency0), expectedCurrency0);
    //     vm.assertEq(Currency.unwrap(poolKey.currency1), expectedCurrency1);
    //     vm.assertEq(poolKey.fee, expectedFee);
    //     vm.assertEq(poolKey.tickSpacing, expectedTickSpacing);
    //     vm.assertEq(info.tickLower(), expectedTickLower);
    //     vm.assertEq(info.tickUpper(), expectedTickUpper);
    // }

    // function assertPositionNotCreated(IPositionManager positionManager, uint256 tokenId) internal view {
    //     (PoolKey memory poolKey, PositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);

    //     vm.assertEq(Currency.unwrap(poolKey.currency0), address(0));
    //     vm.assertEq(Currency.unwrap(poolKey.currency1), address(0));
    //     vm.assertEq(poolKey.fee, 0);
    //     vm.assertEq(poolKey.tickSpacing, 0);
    //     vm.assertEq(info.tickLower(), 0);
    //     vm.assertEq(info.tickUpper(), 0);
    // }
}
