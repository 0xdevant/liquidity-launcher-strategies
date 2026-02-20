// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {MigrationData} from "liquidity-launcher/src/types/MigrationData.sol";
import {TickBounds} from "liquidity-launcher/src/types/PositionTypes.sol";

import {MigratorParameters, Distribution} from "script/common/Types.sol";
import {Log} from "script/common/Log.sol";
import {SSLForTokenLBPStrategyBasicFactory} from "src/SSLForTokenLBPStrategyBasicFactory.sol";
import {ProceedsSplitParameters} from "src/types/ProceedsSplitParameters.sol";

import {FullLaunchTestBase} from "./FullLaunchTestBase.t.sol";
import {Constants} from "./Constants.sol";
import {ILBPStrategyBasicView} from "./ILBPStrategyBasicView.sol";
import {MockSSLForTokenLBPStrategyBasicFactory} from "./mocks/MockSSLForTokenLBPStrategyBasicFactory.sol";
import {SSLForTokenLBPStrategyBasicHarness} from "./mocks/SSLForTokenLBPStrategyBasicHarness.sol";

abstract contract SSLForTokenLBPStrategyBasicTestBase is FullLaunchTestBase, Log {
    using AuctionStepsBuilder for bytes;

    MockSSLForTokenLBPStrategyBasicFactory public sslForTokenLBPStrategyBasicFactory;
    SSLForTokenLBPStrategyBasicHarness public sslForTokenLBP;

    address public proceedsRecipient = makeAddr("proceedsRecipient");

    ProceedsSplitParameters public proceedsSplitParams =
        ProceedsSplitParameters({proceedsSplitMBP: 3e6, proceedsRecipient: proceedsRecipient}); // 30%

    function setUp() public virtual override {
        super.setUp();

        _replaceToTestConfig();

        sslForTokenLBPStrategyBasicFactory = new MockSSLForTokenLBPStrategyBasicFactory(
            IPositionManager(Constants.MAINNET_POSITION_MANAGER), IPoolManager(Constants.MAINNET_POOL_MANAGER)
        );
        _configureLBP(
            address(sslForTokenLBPStrategyBasicFactory),
            abi.encode(_configuration.migratorParams, _configuration.auctionParams, proceedsSplitParams)
        );
        _createAndDistributeToken(_mineSSLForTokenLBPSalt());
        _useSSLForTokenLBP();
    }

    function _replaceToTestConfig() internal {
        uint64 blockNumber = uint64(vm.getBlockNumber());

        // NOTE: input your test configuration here
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
                    fundsRecipient: address(1), // 1 means MSG_SENDER in ActionConstants.sol i.e lbp contract
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
                // 1e7 = 100%, 5e6 = 50%
                tokenSplitToAuction: 5e6, // 50% of 1 billion tokens i.e. 500 million tokens
                auctionFactory: address(auctionFactory),
                positionRecipient: lpRecipient,
                sweepBlock: blockNumber + 1000,
                operator: testOperator,
                createOneSidedTokenPosition: true,
                createOneSidedCurrencyPosition: true
            }),
            distributionParams: Distribution({
                strategy: address(0), amount: Constants.DEFAULT_DISTRIBUTION_AMOUNT, configData: ""
            })
        });
    }

    function _mineSSLForTokenLBPSalt() internal view returns (bytes32 minedSalt) {
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
            IPoolManager(Constants.MAINNET_POOL_MANAGER),
            proceedsSplitParams
        );
        (, minedSalt) = mine(
            address(liquidityLauncher),
            shouldCreateToken ? address(this) : projectTokenOwner,
            address(sslForTokenLBPStrategyBasicFactory),
            Constants.FLAGS,
            type(SSLForTokenLBPStrategyBasicHarness).creationCode,
            encodedConstructorArgs
        );
    }

    function _useSSLForTokenLBP() internal {
        require(address(token) != address(0), "Token not deployed");

        bytes32 saltPassedFromLiquidityLauncher = shouldCreateToken
            ? keccak256(abi.encode(address(this), finalSalt))
            : keccak256(abi.encode(projectTokenOwner, finalSalt));

        sslForTokenLBP = SSLForTokenLBPStrategyBasicHarness(
            payable(sslForTokenLBPStrategyBasicFactory.getLBPAddress(
                    address(token),
                    _configuration.distributionParams.amount,
                    _configuration.distributionParams.configData,
                    saltPassedFromLiquidityLauncher,
                    address(liquidityLauncher)
                ))
        );

        _verifyLBPInitialState(ILBPStrategyBasicView(address(sslForTokenLBP)));
        assertEq(sslForTokenLBP.totalSupply(), Constants.DEFAULT_DISTRIBUTION_AMOUNT);
    }
}

