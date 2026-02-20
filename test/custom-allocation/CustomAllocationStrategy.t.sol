// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LBPStrategyBasicFactory} from "liquidity-launcher/src/distributionStrategies/LBPStrategyBasicFactory.sol";
import {LBPStrategyBasic} from "liquidity-launcher/src/distributionContracts/LBPStrategyBasic.sol";
import {IDistributionContract} from "liquidity-launcher/src/interfaces/IDistributionContract.sol";

import {CustomAllocationStrategy} from "src/custom-allocation/CustomAllocationStrategy.sol";
import {ICustomAllocationStrategy} from "src/interfaces/ICustomAllocationStrategy.sol";
import {FullLaunchTestBase} from "test/FullLaunchTestBase.t.sol";
import {ILBPStrategyBasicView} from "test/ILBPStrategyBasicView.sol";
import {Constants} from "test/Constants.sol";

contract CustomAllocationStrategyTestHarness is CustomAllocationStrategy {
    constructor(address liquidityLauncher) CustomAllocationStrategy(liquidityLauncher) {}

    function LIQUIDITY_LAUNCHER() external view returns (address) {
        return _LIQUIDITY_LAUNCHER;
    }

    function parameters() external view returns (Parameters memory) {
        return _parameters;
    }
}

contract CustomAllocationStrategyTest is FullLaunchTestBase {
    uint256 public constant MAX_ALLOCATION_AMOUNT = Constants.DEFAULT_TOTAL_SUPPLY / 2;

    LBPStrategyBasicFactory lbpStrategyBasicFactory;
    LBPStrategyBasic lbp;
    CustomAllocationStrategyTestHarness customAllocationStrategy;

    address testRecipient = makeAddr("testRecipient");

    function setUp() public override {
        super.setUp();

        // use default config so need to update manually
        _configuration.migratorParams.auctionFactory = address(auctionFactory);

        customAllocationStrategy = new CustomAllocationStrategyTestHarness(address(liquidityLauncher));
        lbpStrategyBasicFactory = new LBPStrategyBasicFactory(
            IPositionManager(Constants.MAINNET_POSITION_MANAGER), IPoolManager(Constants.MAINNET_POOL_MANAGER)
        );

        // deduct amount of total distribution amount for custom strategy to account for the allocation
        _configuration.distributionParams.amount = Constants.DEFAULT_CUSTOM_DISTRIBUTION_AMOUNT;

        _configureLBP(
            address(lbpStrategyBasicFactory), abi.encode(_configuration.migratorParams, _configuration.auctionParams)
        );

        _createAndDistributeTokenWithCustomStrategy(_mineDefaultLBPSalt(), address(customAllocationStrategy));
        _useDefaultLBP();
    }

    function test_InitialState() public view {
        assertEq(customAllocationStrategy.LIQUIDITY_LAUNCHER(), address(liquidityLauncher));
        assertEq(customAllocationStrategy.parameters().tokenAddress, address(0));
        assertEq(customAllocationStrategy.parameters().allocationRecipient, address(0));
        assertEq(customAllocationStrategy.parameters().allocationAmount, 0);
        assertEq(token.balanceOf(allocationRecipient), Constants.DEFAULT_ALLOCATION_AMOUNT);
    }

    function test_initializeDistribution() public {
        vm.prank(address(liquidityLauncher));
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(testRecipient), bytes32(0)
        );

        assertEq(customAllocationStrategy.parameters().tokenAddress, address(token));
        assertEq(customAllocationStrategy.parameters().allocationRecipient, testRecipient);
        assertEq(customAllocationStrategy.parameters().allocationAmount, Constants.DEFAULT_ALLOCATION_AMOUNT);
    }

    function test_initializeDistribution_RevertWhenNotLiquidityLauncher() public {
        vm.expectRevert(ICustomAllocationStrategy.OnlyLiquidityLauncher.selector);
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(testRecipient), bytes32(0)
        );
    }

    function test_initializeDistribution_RevertWhenAllocationSplitTooHigh() public {
        vm.prank(address(liquidityLauncher));
        vm.expectRevert(
            abi.encodeWithSelector(
                ICustomAllocationStrategy.AllocationSplitTooHigh.selector,
                MAX_ALLOCATION_AMOUNT + 1,
                MAX_ALLOCATION_AMOUNT
            )
        );
        customAllocationStrategy.initializeDistribution(
            address(token), MAX_ALLOCATION_AMOUNT + 1, abi.encode(testRecipient), bytes32(0)
        );
    }

    function test_initializeDistribution_RevertWhenInvalidRecipient() public {
        vm.prank(address(liquidityLauncher));
        vm.expectRevert(ICustomAllocationStrategy.InvalidRecipient.selector);
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(address(0)), bytes32(0)
        );
    }

    function test_onTokensReceived_FullFlow() public {
        uint256 tokenBalanceBefore = token.balanceOf(testRecipient);

        deal(address(token), address(liquidityLauncher), Constants.DEFAULT_ALLOCATION_AMOUNT);

        vm.startPrank(address(liquidityLauncher));
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(testRecipient), bytes32(0)
        );
        token.transfer(address(customAllocationStrategy), Constants.DEFAULT_ALLOCATION_AMOUNT);

        vm.expectEmit(address(customAllocationStrategy));
        emit ICustomAllocationStrategy.TokensAllocated(
            address(token), testRecipient, Constants.DEFAULT_ALLOCATION_AMOUNT
        );
        customAllocationStrategy.onTokensReceived();
        vm.stopPrank();

        assertEq(token.balanceOf(address(customAllocationStrategy)), 0);
        assertEq(token.balanceOf(testRecipient), tokenBalanceBefore + Constants.DEFAULT_ALLOCATION_AMOUNT);
        assertEq(customAllocationStrategy.parameters().tokenAddress, address(0));
        assertEq(customAllocationStrategy.parameters().allocationRecipient, address(0));
        assertEq(customAllocationStrategy.parameters().allocationAmount, 0);
    }

    function test_onTokensReceived_FullFlow_SecondDistributionAfterParametersCleared() public {
        test_onTokensReceived_FullFlow();

        address newRecipient = makeAddr("newRecipient");

        deal(address(token), address(liquidityLauncher), Constants.DEFAULT_ALLOCATION_AMOUNT);
        vm.startPrank(address(liquidityLauncher));
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(newRecipient), bytes32(0)
        );
        token.transfer(address(customAllocationStrategy), Constants.DEFAULT_ALLOCATION_AMOUNT);

        customAllocationStrategy.onTokensReceived();
        vm.stopPrank();

        assertEq(token.balanceOf(address(customAllocationStrategy)), 0);
        assertEq(token.balanceOf(newRecipient), Constants.DEFAULT_ALLOCATION_AMOUNT);
        assertEq(customAllocationStrategy.parameters().tokenAddress, address(0));
        assertEq(customAllocationStrategy.parameters().allocationRecipient, address(0));
        assertEq(customAllocationStrategy.parameters().allocationAmount, 0);
    }

    function test_onTokensReceived_RevertWhenNotLiquidityLauncher() public {
        vm.expectRevert(ICustomAllocationStrategy.OnlyLiquidityLauncher.selector);
        customAllocationStrategy.onTokensReceived();
    }

    function test_onTokensReceived_RevertWhenInvalidAmountReceived() public {
        vm.startPrank(address(liquidityLauncher));
        customAllocationStrategy.initializeDistribution(
            address(token), Constants.DEFAULT_ALLOCATION_AMOUNT, abi.encode(testRecipient), bytes32(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IDistributionContract.InvalidAmountReceived.selector, Constants.DEFAULT_ALLOCATION_AMOUNT, 0
            )
        );
        customAllocationStrategy.onTokensReceived();
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
        assertEq(lbp.totalSupply(), Constants.DEFAULT_CUSTOM_DISTRIBUTION_AMOUNT);
        assertEq(
            lbp.reserveSupply(),
            Constants.DEFAULT_CUSTOM_DISTRIBUTION_AMOUNT - _configuration.distributionParams.amount
                * _configuration.migratorParams.tokenSplitToAuction / 1e7
        );
    }
}
