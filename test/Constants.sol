// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

abstract contract Constants {
    // Constants
    address constant MAINNET_LIQUIDITY_LAUNCHER = 0x00000008412db3394C91A5CbD01635c6d140637C;
    address constant MAINNET_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant MAINNET_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    address constant MAINNET_LBP_STRATEGY_BASIC_FACTORY = 0xbbbb6FFaBCCb1EaFD4F0baeD6764d8aA973316B6;
    address constant BASE_LBP_STRATEGY_BASIC_FACTORY = 0xC46143aE2801b21B8C08A753f9F6b52bEaD9C134;

    address constant BASE_LIQUIDITY_LAUNCHER = 0x00000008412db3394C91A5CbD01635c6d140637C;
    address constant BASE_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant BASE_POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;

    // not sure if liquidity launcher is deployed yet on base sepolia
    address constant BASE_SEPOLIA_LIQUIDITY_LAUNCHER = 0x00000008412db3394C91A5CbD01635c6d140637C;
    address constant BASE_SEPOLIA_POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant BASE_SEPOLIA_POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;

    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    // Default values
    uint128 constant DEFAULT_TOTAL_SUPPLY = 1_000_000_000e18; // 1 billion tokens
    uint128 constant DEFAULT_DISTRIBUTION_AMOUNT = DEFAULT_TOTAL_SUPPLY;
    uint128 constant DEFAULT_ALLOCATION_AMOUNT = 100_000_000e18; // 100 million tokens
    uint128 constant DEFAULT_CUSTOM_DISTRIBUTION_AMOUNT = DEFAULT_TOTAL_SUPPLY - DEFAULT_ALLOCATION_AMOUNT;
    uint128 constant DEFAULT_REQUIRED_CURRENCY_RAISED = 30e18; // 30 Currency units
    uint24 constant DEFAULT_TOKEN_SPLIT = 5e6; // selling 50% of 1 billion tokens i.e. 500 million tokens

    uint256 constant FORK_BLOCK = 23097193;
    uint256 public constant FLOOR_PRICE = (1 << FixedPoint96.RESOLUTION) / 2_000; // 0.0005 currency units = 1 token
    uint256 public constant TICK_SPACING = (1 << FixedPoint96.RESOLUTION) / 2_000; // 0.0005 currency units = 1 tick

    uint8 constant DEFAULT_DECIMALS = 18;
    uint160 constant FLAGS = uint160(Hooks.BEFORE_INITIALIZE_FLAG);
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Test token address (make it > address(0) but < DAI)
    address constant TEST_TOKEN_ADDRESS = 0x1111111111111111111111111111111111111111;

    uint160 constant HOOK_PERMISSION_COUNT = 14;
    uint160 internal constant CLEAR_ALL_HOOK_PERMISSIONS_MASK = ~uint160(0) << (HOOK_PERMISSION_COUNT);
}
