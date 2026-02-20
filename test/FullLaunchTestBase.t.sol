// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";
import {ContinuousClearingAuctionFactory} from "continuous-clearing-auction/src/ContinuousClearingAuctionFactory.sol";
import {
    IContinuousClearingAuction,
    AuctionParameters
} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {ValueX7} from "continuous-clearing-auction/src/libraries/CheckpointLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LiquidityLauncher} from "liquidity-launcher/src/LiquidityLauncher.sol";
import {UERC20Factory} from "liquidity-launcher/src/token-factories/uerc20-factory/factories/UERC20Factory.sol";
import {
    UERC20Metadata
} from "liquidity-launcher/src/token-factories/uerc20-factory/libraries/UERC20MetadataLibrary.sol";
import {Distribution} from "liquidity-launcher/src/types/Distribution.sol";
import {MockERC20} from "liquidity-launcher/test/mocks/MockERC20.sol";

import {MigratorParameters} from "script/common/Types.sol";
import {ILBPStrategyBasicView} from "./ILBPStrategyBasicView.sol";
import {Constants} from "./Constants.sol";
import {Config} from "./Config.sol";

abstract contract FullLaunchTestBase is Config {
    using AuctionStepsBuilder for bytes;
    using FixedPointMathLib for *;

    // Events
    event Notified(bytes data);
    event Migrated(PoolKey indexed key, uint160 initialSqrtPriceX96);

    IAllowanceTransfer permit2;
    LiquidityLauncher liquidityLauncher;
    UERC20Factory uerc20Factory;

    ContinuousClearingAuctionFactory auctionFactory;

    MockERC20 token;
    MockERC20 implToken;

    uint256 nextTokenId;

    bytes32 finalSalt;

    function setUp() public virtual override {
        // load default config
        super.setUp();

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), Constants.FORK_BLOCK);
        _setupContracts();

        // // specify how many tokens to distribute
        // _deployLBPStrategy(Constants.DEFAULT_DISTRIBUTION_AMOUNT);
    }

    function _setupContracts() internal {
        permit2 = IAllowanceTransfer(Constants.PERMIT2);
        liquidityLauncher = new LiquidityLauncher(permit2);
        uerc20Factory = new UERC20Factory();
        auctionFactory = new ContinuousClearingAuctionFactory();

        nextTokenId = IPositionManager(Constants.MAINNET_POSITION_MANAGER).nextTokenId();

        // Give test contract some DAI
        deal(Constants.DAI, address(this), 1_000e18);
    }

    // ============ Helpers methods ============

    // the order is _configureLBP() -> _createAndDistributeToken(_mineDefaultLBPSalt()) -> _useDefaultLBP()
    function _configureLBP(address lbpFactory, bytes memory configData) internal {
        _configuration.distributionParams.strategy = lbpFactory;
        _configuration.distributionParams.configData = configData;
    }

    function _createAndDistributeToken(bytes32 minedSalt) internal {
        emit log_string("Creating and Distributing Token...");

        finalSalt = minedSalt;

        if (shouldCreateToken) {
            emit log_string("Using New Token...");
            UERC20Metadata memory metadata = UERC20Metadata({
                description: _configuration.tokenCreationParams.description,
                website: _configuration.tokenCreationParams.website,
                image: _configuration.tokenCreationParams.image
            });

            address precomputedAddress = computeUERC20Address(
                _configuration.tokenCreationParams.name,
                _configuration.tokenCreationParams.symbol,
                address(liquidityLauncher)
            );

            // assign to the token instance
            token = MockERC20(precomputedAddress);

            bytes[] memory calls = new bytes[](2);
            calls[0] = abi.encodeWithSelector(
                LiquidityLauncher.createToken.selector,
                address(uerc20Factory),
                _configuration.tokenCreationParams.name,
                _configuration.tokenCreationParams.symbol,
                Constants.DEFAULT_DECIMALS,
                _configuration.tokenCreationParams.initialSupply,
                address(liquidityLauncher),
                abi.encode(metadata)
            );
            calls[1] = abi.encodeWithSelector(
                LiquidityLauncher.distributeToken.selector,
                precomputedAddress,
                _configuration.distributionParams,
                false,
                finalSalt
            );

            liquidityLauncher.multicall(calls);
        } else {
            _useExistingToken();
            emit log_string("Using Existing Token...");

            // a token already deployed from _useExistingToken()
            assertEq(token.balanceOf(address(projectTokenOwner)), _configuration.tokenCreationParams.initialSupply);

            vm.prank(projectTokenOwner);
            liquidityLauncher.distributeToken(address(token), _configuration.distributionParams, true, finalSalt);

            uint128 distributionAmount = _configuration.distributionParams.amount;
            assertEq(token.balanceOf(address(liquidityLauncher)), 0);
            assertEq(
                token.balanceOf(address(projectTokenOwner)),
                _configuration.tokenCreationParams.initialSupply - distributionAmount
            );
        }

        require(address(token) != address(0), "Token not deployed");
    }

    function _createAndDistributeTokenWithCustomStrategy(bytes32 minedSalt, address customStrategy) internal {
        emit log_string("Creating and Distributing Token with Custom Strategy...");

        finalSalt = minedSalt;

        Distribution memory customDistribution = Distribution({
            strategy: customStrategy,
            amount: Constants.DEFAULT_ALLOCATION_AMOUNT,
            configData: abi.encode(allocationRecipient)
        });

        if (shouldCreateToken) {
            emit log_string("Using New Token...");
            UERC20Metadata memory metadata = UERC20Metadata({
                description: _configuration.tokenCreationParams.description,
                website: _configuration.tokenCreationParams.website,
                image: _configuration.tokenCreationParams.image
            });

            address precomputedAddress = computeUERC20Address(
                _configuration.tokenCreationParams.name,
                _configuration.tokenCreationParams.symbol,
                address(liquidityLauncher)
            );

            // assign to the token instance
            token = MockERC20(precomputedAddress);

            bytes[] memory calls = new bytes[](3);
            calls[0] = abi.encodeWithSelector(
                LiquidityLauncher.createToken.selector,
                address(uerc20Factory),
                _configuration.tokenCreationParams.name,
                _configuration.tokenCreationParams.symbol,
                Constants.DEFAULT_DECIMALS,
                _configuration.tokenCreationParams.initialSupply,
                address(liquidityLauncher),
                abi.encode(metadata)
            );
            calls[1] = abi.encodeWithSelector(
                LiquidityLauncher.distributeToken.selector,
                precomputedAddress,
                _configuration.distributionParams,
                false,
                finalSalt
            );
            calls[2] = abi.encodeWithSelector(
                LiquidityLauncher.distributeToken.selector,
                precomputedAddress,
                customDistribution,
                false,
                // the salt doesn't matter for custom distribution
                bytes32(0)
            );

            liquidityLauncher.multicall(calls);
        } else {
            _useExistingToken();
            emit log_string("Using Existing Token...");

            // a token already deployed from _useExistingToken()
            assertEq(token.balanceOf(address(projectTokenOwner)), _configuration.tokenCreationParams.initialSupply);

            vm.startPrank(projectTokenOwner);
            // send `DEFAULT_CUSTOM_DISTRIBUTION_AMOUNT` to default lbp
            liquidityLauncher.distributeToken(address(token), _configuration.distributionParams, true, finalSalt);
            // send `DEFAULT_ALLOCATION_AMOUNT` to custom strategy
            liquidityLauncher.distributeToken(address(token), customDistribution, true, bytes32(0));
            vm.stopPrank();

            uint128 distributionAmount = _configuration.distributionParams.amount;
            assertEq(token.balanceOf(address(liquidityLauncher)), 0);
            assertEq(
                token.balanceOf(address(projectTokenOwner)),
                _configuration.tokenCreationParams.initialSupply - distributionAmount
                    - Constants.DEFAULT_ALLOCATION_AMOUNT
            );
        }

        require(address(token) != address(0), "Token not deployed");
    }

    function _useExistingToken() internal {
        // Deploy token and give supply to liquidity launcher
        token = MockERC20(Constants.TEST_TOKEN_ADDRESS);
        TokenCreationParams memory tokenCreationParams = _configuration.tokenCreationParams;
        implToken = new MockERC20(
            tokenCreationParams.name, tokenCreationParams.symbol, tokenCreationParams.initialSupply, projectTokenOwner
        );
        vm.etch(Constants.TEST_TOKEN_ADDRESS, address(implToken).code);
        // still need to deal the token directly since implToken is just for etching and its mint is from another contract address
        deal(address(token), projectTokenOwner, tokenCreationParams.initialSupply);

        // mock totalSupply due to `token` not having the constructor states after etched to `implToken`
        vm.mockCall(
            address(Constants.TEST_TOKEN_ADDRESS),
            token.totalSupply.selector,
            abi.encode(Constants.DEFAULT_TOTAL_SUPPLY)
        );

        // Set up permit2 approval
        vm.startPrank(projectTokenOwner);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(liquidityLauncher), type(uint160).max, 0);
        vm.stopPrank();
    }

    function _verifyLBPInitialState(ILBPStrategyBasicView lbpView) internal view virtual {
        assertEq(lbpView.token(), address(token));
        assertEq(lbpView.currency(), _configuration.migratorParams.currency);
        assertEq(lbpView.positionRecipient(), _configuration.migratorParams.positionRecipient);
        assertEq(lbpView.migrationBlock(), _configuration.migratorParams.migrationBlock);
        assertEq(lbpView.positionManager(), Constants.MAINNET_POSITION_MANAGER);
        assertEq(lbpView.poolManager(), Constants.MAINNET_POOL_MANAGER);
        assertEq(lbpView.poolLPFee(), _configuration.migratorParams.poolLPFee);
        assertEq(lbpView.poolTickSpacing(), _configuration.migratorParams.poolTickSpacing);
        assertEq(lbpView.auctionParameters(), _configuration.auctionParams);
    }

    // // Helper to setup with custom total supply
    // function setupWithSupply(uint128 totalSupply) internal {
    //     _deployLBPStrategy(totalSupply);
    // }

    // // Helper to setup with custom currency (e.g., DAI)
    // function setupWithCurrency(address currency) internal {
    //     _configuration.migratorParams = createMigratorParams(
    //         currency,
    //         _configuration.migratorParams.poolLPFee,
    //         _configuration.migratorParams.poolTickSpacing,
    //         _configuration.migratorParams.tokenSplitToAuction,
    //         _configuration.migratorParams.positionRecipient,
    //         _configuration.migratorParams.migrationBlock,
    //         _configuration.migratorParams.sweepBlock,
    //         _configuration.migratorParams.operator,
    //         _configuration.migratorParams.createOneSidedTokenPosition,
    //         _configuration.migratorParams.createOneSidedCurrencyPosition
    //     );
    //     createAuctionParamsWithCurrency(currency);
    //     _deployLBPStrategy(Constants.DEFAULT_TOTAL_SUPPLY);
    // }

    // // Helper to setup with custom total supply and token split
    // function setupWithSupplyAndTokenSplit(uint128 totalSupply, uint24 tokenSplit, address currency) internal {
    //     _configuration.migratorParams = createMigratorParams(
    //         currency, // ETH as currency (same as default)
    //         500, // fee (same as default)
    //         1, // tick spacing (same as default)
    //         tokenSplit, // Use custom tokenSplit
    //         address(3), // position recipient (same as default),
    //         uint64(block.number + 500), // migration block
    //         uint64(block.number + 1_000), // sweep block
    //         testOperator, // operator
    //         true, // createOneSidedTokenPosition
    //         true // createOneSidedCurrencyPosition
    //     );
    //     createAuctionParamsWithCurrency(currency);
    //     _deployLBPStrategy(totalSupply);
    // }

    // function createAuctionParamsWithCurrency(address currency) internal {
    //     bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);

    //     _configuration.auctionParams = abi.encode(
    //         AuctionParameters({
    //             currency: currency, // Currency (could be ETH or ERC20)
    //             tokensRecipient: makeAddr("tokensRecipient"), // Some valid address
    //             fundsRecipient: address(1),
    //             startBlock: uint64(block.number),
    //             endBlock: uint64(block.number + 100),
    //             claimBlock: uint64(block.number + 100 + 10),
    //             tickSpacing: Constants.TICK_SPACING,
    //             validationHook: address(0), // No validation hook
    //             floorPrice: Constants.FLOOR_PRICE,
    //             requiredCurrencyRaised: 0,
    //             auctionStepsData: auctionStepsData
    //         })
    //     );
    // }

    function mine(
        address liquidityLauncherAddress,
        address userCaller,
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) public view returns (address, bytes32) {
        flags = flags & HookMiner.FLAG_MASK; // mask for only the bottom 14 bits
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        // memory reset hack
        bytes32 free_mem;
        assembly ("memory-safe") {
            free_mem := mload(0x40)
        }
        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            bytes32 originalSalt = bytes32(i);
            bytes32 firstSalt = keccak256(abi.encode(userCaller, originalSalt));
            bytes32 secondSalt = keccak256(abi.encode(liquidityLauncherAddress, firstSalt));
            address hookAddress = HookMiner.computeAddress(deployer, uint256(secondSalt), creationCodeWithArgs);

            // if the hook's bottom 14 bits match the desired flags AND the address does not have bytecode, we found a match
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, originalSalt);
            }
            assembly ("memory-safe") {
                mstore(0x40, free_mem)
            }
        }
        revert("HookMiner: could not find salt");
    }

    function computeUERC20Address(string memory name, string memory symbol, address creator)
        internal
        view
        returns (address)
    {
        // getGraffiti(address originalCreator)
        bytes32 graffiti = liquidityLauncher.getGraffiti(address(this));

        return uerc20Factory.getUERC20Address(name, symbol, Constants.DEFAULT_DECIMALS, creator, graffiti);
    }

    // ============ Core Bid Submission Helpers ============

    /// @notice Submits a bid for ETH auction
    /// @dev Handles ETH transfer, event emission, and bid ID validation
    function _submitBid(
        IContinuousClearingAuction auction,
        address bidder,
        uint128 tokenAmount,
        uint256 priceX96,
        uint256 prevPriceX96,
        uint256 expectedBidId
    ) internal returns (uint256) {
        uint128 inputAmount = tokenAmount;

        vm.deal(bidder, inputAmount);

        vm.prank(bidder);
        uint256 bidId = auction.submitBid{value: inputAmount}(
            priceX96, // maxPrice
            inputAmount, // amount
            bidder, // owner
            prevPriceX96, // prevTickPrice hint
            bytes("") // hookData
        );

        assertEq(bidId, expectedBidId);

        return bidId;
    }

    /// @notice Submits a bid for ERC20 auction
    /// @dev Assumes Permit2 approval is already set up
    function _submitBidNonEth(
        IContinuousClearingAuction auction,
        address bidder,
        uint128 tokenAmount,
        uint256 priceX96,
        uint256 prevPriceX96,
        uint256 expectedBidId
    ) internal returns (uint256) {
        uint128 inputAmount = tokenAmount;

        vm.prank(bidder);
        uint256 bidId = auction.submitBid(
            priceX96, // maxPrice
            inputAmount, // amount
            bidder, // owner
            prevPriceX96, // prevTickPrice hint
            bytes("") // hookData
        );

        assertEq(bidId, expectedBidId);

        return bidId;
    }
}
