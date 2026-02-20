# Liquidity Launcher Strategy Contracts

## Overview

This is a repo built on top of Uniswap's [Liquidity Launcher](https://github.com/Uniswap/liquidity-launcher). You can find here the:

1. smart contracts for custom LBP strategy
2. test suite for simulating the full launch flow

This repo uses foundry to allow integrators to configure any specific sets of token creation params, distribution params, auction params and migration params in order to understand what's exactly happening between different stages of the launch flow e.g. how the token is allocated, how the clearing price during Continuius Clearing Auction changes etc, under either a fork testing environemnt or a Tenderly virtual testnet environment.

## Get Started

```bash
# Clone the repository with submodules
git clone --recurse-submodules <repository-url>
cd liquidity-launcher-strategies

# If you already cloned without submodules
git submodule update --init --recursive

# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# fall back to previous working version due to latest version not working on forge build
foundryup --install 1.4.4
foundryup --use v1.4.4

# Run tests
forge test --isolate -vvv
```

The project requires the following environment variable for fork testing:

- `MAINNET_RPC_URL`: An Ethereum mainnet RPC endpoint for fork testing

If you want the tests to run faster, reduce the fuzz runs in `foundry.toml`

```toml
[profile.default.fuzz]
runs = 100
```

## Usage

### Deployment

`SSLForTokenLBPStrategyBasicFactory.sol`

Specify the addresses for the constructor in `DeployTokenSSLLBPStrategyBasicFactory.s.sol`:

```solidity
address public constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
```

Deploy and verify the contract:

```bash
# may need to specify Etherscan API Key for certain network by --etherscan-api-key
forge script script/DeploySSLForTokenLBPStrategyBasicFactory.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast --verify
```

Deployment details will be recorded in `deployments/SSLForTokenLBPStrategyBasicFactory.md`

### Fork Testing Configuration

1. Run `cp .env.example .env`

2. Inside `.env`
   - Put `SHOULD_CREATE_TOKEN=FALSE` if you want to simulate using an existing token
   - Put a Tenderly Virtual testnet / Node RPC URL for `MAINNET_RPC_URL`

3. Make changes in the params `_configuration` in the respective test file e.g. `FullLaunchTest.t.sol`

```solidity
    tokenCreationParams: TokenCreationParams({
        name: "Full Launch Token",
        symbol: "FLT",
        initialSupply: Constants.DEFAULT_TOTAL_SUPPLY,
        ...
    }),
    auctionParams: abi.encode(
        AuctionParameters({
            ...
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 100),
            claimBlock: uint64(block.number + 100 + 10),
            tickSpacing: (1 << FixedPoint96.RESOLUTION) / 2_000,
            validationHook: address(0), // No validation hook
            floorPrice: (1 << FixedPoint96.RESOLUTION) / 2_000, // 0.0005 ETH per token
            requiredCurrencyRaised: 30e18, // 30 ETH
            // 1000 mps = 1 basis point so 100e3 = 100 basis points i.e. 1% of supply per block
            auctionStepsData: AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50)
        })
    ),
    ...
```

**For auction params:**

`floorPrice` - Starting floor price for the auction, unit is in sqrtPriceX96 i.e. `(1 << FixedPoint96.RESOLUTION)` indicates 1 Currency = 1 token

`requiredCurrencyRaised` - Amount of currency required to be raised for the auction to graduate

`auctionStepsData` - token issuance schedule, e.g. 1000 mps = 1 basis point so 100e3 = 100 basis points i.e. 1% of supply per block, 50% of supply for 50 blocks

#### Test

Run foundry test for an example launch flow simulation

```bash
forge test --mt test_full_launch_MarketOrderWithMaxCurrencyFromOneBid -vvv
```

### Tenderly Virtual Testnet Configuration

0. Configure parameters in `TenderlyConstants.sol`
1. Create full token launch via `LiquidityLauncher`'s `createToken` and `distributeToken`

```bash
forge script script/tenderly/CreateTokenLaunch.s.sol --private-key $PRIVATE_KEY --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC_URL --broadcast --slow
```

2. Submit bids by a specific token amount and max price

```bash
forge script script/tenderly/SubmitBid.s.sol --private-key $PRIVATE_KEY --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC_URL --broadcast --slow
```

3. Migrate to Uniswap v4 pool once the auction is ready to graduate

```bash
forge script script/tenderly/Migrate.s.sol --private-key $PRIVATE_KEY --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC_URL --broadcast --slow
```

## Important Safety Notes

⚠️ **Rebasing Tokens and Fee-on-Transfer Tokens are NOT compatible with LiquidityLauncher.** The system is designed for standard ERC20 tokens and will not function correctly with tokens that have dynamic balances or transfer fees.

⚠️ **Always use multicall for atomic token creation and distribution.** When creating and distributing tokens, batch both operations in a single transaction with `payerIsUser = false` to prevent tokens from sitting unprotected in the LiquidityLauncher contract where anyone could call `distribute()`.
