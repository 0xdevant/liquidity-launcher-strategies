// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MigratorParameters} from "liquidity-launcher/src/types/MigratorParameters.sol";
import {Distribution} from "liquidity-launcher/src/types/Distribution.sol";

abstract contract Types {
    struct Configuration {
        TokenCreationParams tokenCreationParams;
        bytes auctionParams;
        MigratorParameters migratorParams;
        Distribution distributionParams;
    }

    struct TokenCreationParams {
        // mint params
        string name;
        string symbol;
        uint256 initialSupply;
        address recipient;
        // metadata
        string description;
        string website;
        string image;
    }
}
