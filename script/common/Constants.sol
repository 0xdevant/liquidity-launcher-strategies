// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

abstract contract Constants {
    address public constant TEST_ANT_CALLER = 0x701F7fdfabd99DFC3c0b2B226fD379d4Be93DFf3;
    uint160 public constant FLAGS = uint160(Hooks.BEFORE_INITIALIZE_FLAG);

    uint256 public constant ONE_DAY_BLOCKS = 86400 / 12;
    uint256 public constant THOUSAND_BLOCKS = 1000;
}
