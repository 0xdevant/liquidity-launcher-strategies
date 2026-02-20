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

abstract contract TenderlyConstants is Constants, Types {
    using AuctionStepsBuilder for bytes;

    IPoolManager public poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager public positionManager = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);

    ILiquidityLauncher public liquidityLauncher = ILiquidityLauncher(0x00000008412db3394C91A5CbD01635c6d140637C);

    // deployed on Virtual Testnet
    IUERC20Factory public uerc20Factory = IUERC20Factory(0x8FE82aB6D1C9C0574a3E2954c4C96C9136Aac10A);
    IDistributionStrategy public lbpStrategyBasicFactory =
        IDistributionStrategy(0x827A2c1F489ac1D340cB69d2C43Ba8e288375B68);

    address public constant AUCTION_FACTORY = 0x251Dda5Ff4ef823AD3752fe2d7100cD91b1EDDfE;

    // NOTE: change these for every new auction!
    address public constant LBP_STRATEGY_BASIC = 0x0524571611f2504a2F70484217cE08B67F6c6000;
    address public constant AUCTION = 0x3d77eDD9989be6e2F840C5EC5b3CA18358fA98AA;

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
            name: "Tenderly Full Launch Token 0422",
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
