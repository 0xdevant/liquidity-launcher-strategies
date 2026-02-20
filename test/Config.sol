// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";

import {Types, MigratorParameters, Distribution} from "script/common/Types.sol";
import {Constants} from "./Constants.sol";

abstract contract Config is Test, Constants, Types {
    using AuctionStepsBuilder for bytes;

    // wallet who owns the token supply before launch if `shouldCreateToken` is false
    address projectTokenOwner = makeAddr("projectTokenOwner");
    address testOperator = makeAddr("testOperator");
    address lpRecipient = makeAddr("lpRecipient");
    address leftoverTokensRecipient = makeAddr("leftoverTokensRecipient");
    address allocationRecipient = makeAddr("allocationRecipient");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    bool shouldCreateToken;

    Configuration internal _configuration;

    function setUp() public virtual {
        shouldCreateToken = vm.envOr("SHOULD_CREATE_TOKEN", true);

        _configuration = _setupDefaultParams();
    }

    function _setupDefaultParams() internal view returns (Configuration memory) {
        uint64 blockNumber = uint64(vm.getBlockNumber());

        return Configuration({
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
                    tickSpacing: Constants.TICK_SPACING,
                    validationHook: address(0), // No validation hook
                    floorPrice: Constants.FLOOR_PRICE,
                    requiredCurrencyRaised: Constants.DEFAULT_REQUIRED_CURRENCY_RAISED,
                    // 1000 mps = 1 basis point so 100e3 = 100 basis points i.e. 1% of supply per 50 blocks
                    auctionStepsData: AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50)
                })
            ),
            migratorParams: MigratorParameters({
                migrationBlock: blockNumber + 500,
                currency: address(0),
                poolLPFee: 500,
                poolTickSpacing: 1,
                tokenSplitToAuction: Constants.DEFAULT_TOKEN_SPLIT,
                // this will be replaced after auction factory is deployed
                auctionFactory: address(0),
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
}
