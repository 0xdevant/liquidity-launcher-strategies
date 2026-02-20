// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";

import {ILiquidityLauncher} from "liquidity-launcher/src/interfaces/ILiquidityLauncher.sol";
import {
    UERC20Metadata
} from "liquidity-launcher/src/token-factories/uerc20-factory/libraries/UERC20MetadataLibrary.sol";
import {IUERC20Factory} from "liquidity-launcher/src/token-factories/uerc20-factory/interfaces/IUERC20Factory.sol";
import {IDistributionStrategy} from "liquidity-launcher/src/interfaces/IDistributionStrategy.sol";

import {Constants} from "./Constants.sol";
import {MigratorParameters, Distribution, Types} from "./Types.sol";

abstract contract SepoliaConstants is Constants, Types {
    using AuctionStepsBuilder for bytes;

    IPoolManager public poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    IPositionManager public positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);

    ILiquidityLauncher public liquidityLauncher = ILiquidityLauncher(0x00000008412db3394C91A5CbD01635c6d140637C);
    IUERC20Factory public uerc20Factory = IUERC20Factory(0x25C8Cc18bA28310087729a355FF884e4058f08f9);
    IDistributionStrategy public lbpStrategyBasicFactory =
        IDistributionStrategy(0xE4E2474083638e047b0d380E6787a2dfa7dB1A74);

    address public constant AUCTION_FACTORY = 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D;

    // NOTE: change this!
    address public constant AUCTION = 0x750A003b39FD9018Be7C0Ba71191F746d5567D45;

    MigratorParameters public migratorParams = MigratorParameters({
        migrationBlock: uint64(block.number + THOUSAND_BLOCKS + 500),
        currency: address(0),
        poolLPFee: 500,
        poolTickSpacing: 1,
        // 1e7 = 100%, 5e6 = 50%
        tokenSplitToAuction: 5e6, // 50% of 1 billion tokens i.e. 500 million tokens
        // this will be replaced after auction factory is deployed
        auctionFactory: AUCTION_FACTORY,
        positionRecipient: address(this),
        sweepBlock: uint64(block.number + THOUSAND_BLOCKS + 1000),
        operator: TEST_ANT_CALLER,
        createOneSidedTokenPosition: true,
        createOneSidedCurrencyPosition: true
    });

    bytes public auctionParams = abi.encode(
        AuctionParameters({
            currency: address(0), // ETH
            tokensRecipient: TEST_ANT_CALLER, // Some valid address
            fundsRecipient: address(1), // 1 means MSG_SENDER in ActionConstants.sol
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + THOUSAND_BLOCKS),
            claimBlock: uint64(block.number + THOUSAND_BLOCKS + 10),
            tickSpacing: (1 << FixedPoint96.RESOLUTION) / 2_000,
            validationHook: address(0), // No validation hook
            floorPrice: (1 << FixedPoint96.RESOLUTION) / 2_000, // 0.0005 ETH per token
            requiredCurrencyRaised: 1e18, // 1 ETH
            // 1000 mps = 1 basis point so 100e3 = 100 basis points i.e. 1% of supply per block
            auctionStepsData: AuctionStepsBuilder.init().addStep(100e2, 1000)
        })
    );

    // BOTH PARAMS ABOVE MUST BE BEFORE Configuration init

    Configuration public configuration = Configuration({
        tokenCreationParams: TokenCreationParams({
            name: "Full Launch Token 0350",
            symbol: "FLT",
            initialSupply: 1_000_000_000e18,
            recipient: address(liquidityLauncher),
            description: "Full launch token",
            website: "https://test.com",
            image: "https://test.com/image.png"
        }),
        auctionParams: auctionParams,
        migratorParams: migratorParams,
        distributionParams: Distribution({
            strategy: address(lbpStrategyBasicFactory),
            amount: 500_000_000e18,
            configData: abi.encode(migratorParams, auctionParams)
        })
    });

    UERC20Metadata public metadata = UERC20Metadata({
        description: configuration.tokenCreationParams.description,
        website: configuration.tokenCreationParams.website,
        image: configuration.tokenCreationParams.image
    });
}
