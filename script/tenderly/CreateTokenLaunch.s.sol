// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {LBPStrategyBasic} from "liquidity-launcher/src/distributionContracts/LBPStrategyBasic.sol";
import {LiquidityLauncher} from "liquidity-launcher/src/LiquidityLauncher.sol";
import {IDistributionContract} from "liquidity-launcher/src/interfaces/IDistributionContract.sol";
import {IMulticall} from "liquidity-launcher/src/interfaces/IMulticall.sol";

import {TenderlyConstants} from "../common/TenderlyConstants.sol";
import {MineHookSalts} from "../common/MineHookSalts.sol";
import {Log} from "../common/Log.sol";

contract CreateTokenLaunchTenderlyScript is Script, TenderlyConstants, MineHookSalts, Log {
    function run() public {
        vm.startBroadcast();

        address precomputedAddress = uerc20Factory.getUERC20Address(
            configuration.tokenCreationParams.name,
            configuration.tokenCreationParams.symbol,
            18,
            address(liquidityLauncher),
            liquidityLauncher.getGraffiti(TEST_ANT_CALLER)
        );

        bytes memory encodedConstructorArgs = abi.encode(
            precomputedAddress,
            uint128(configuration.distributionParams.amount),
            migratorParams,
            auctionParams,
            positionManager,
            poolManager
        );

        address hookAddress;
        bytes32 finalSalt;
        (hookAddress, finalSalt) = mine(
            address(liquidityLauncher),
            TEST_ANT_CALLER,
            address(lbpStrategyBasicFactory),
            FLAGS,
            type(LBPStrategyBasic).creationCode,
            encodedConstructorArgs
        );

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            LiquidityLauncher.createToken.selector,
            address(uerc20Factory),
            configuration.tokenCreationParams.name,
            configuration.tokenCreationParams.symbol,
            18,
            configuration.tokenCreationParams.initialSupply,
            address(liquidityLauncher),
            abi.encode(metadata)
        );
        calls[1] = abi.encodeWithSelector(
            LiquidityLauncher.distributeToken.selector,
            precomputedAddress,
            configuration.distributionParams,
            false,
            finalSalt
        );

        bytes[] memory multicallResult = IMulticall(address(liquidityLauncher)).multicall(calls);
        assertEq(abi.decode(multicallResult[0], (address)), precomputedAddress);
        address deployedLbp = address(abi.decode(multicallResult[1], (IDistributionContract)));
        recordDeployment(precomputedAddress, deployedLbp, "Tenderly");

        vm.stopBroadcast();
    }
}
