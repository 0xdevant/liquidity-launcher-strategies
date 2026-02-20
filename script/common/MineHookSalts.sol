// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./Constants.sol";

abstract contract MineHookSalts is Constants {
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

        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            bytes32 salt = bytes32(i);
            bytes32 firstSalt = keccak256(abi.encode(userCaller, salt));
            bytes32 secondSalt = keccak256(abi.encode(liquidityLauncherAddress, firstSalt));
            address hookAddress = HookMiner.computeAddress(deployer, uint256(secondSalt), creationCodeWithArgs);

            // if the hook's bottom 14 bits match the desired flags AND the address does not have bytecode, we found a match
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, salt);
            }
        }
        revert("HookMiner: could not find salt");
    }
}
