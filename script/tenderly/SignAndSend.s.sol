// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
// import {
//     IContinuousClearingAuction
// } from "lib/continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";

import {TenderlyConstants, AuctionParameters} from "../common/TenderlyConstants.sol";
import {Helpers} from "../common/Helpers.sol";

interface IContinuousClearingAuction {
    function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        external
        payable
        returns (uint256 bidId);
}

contract SignAndSendScript is Script, TenderlyConstants {
    using Helpers for IContinuousClearingAuction;

    function run() public {
        // AuctionParameters memory params = Helpers.getAuctionParams(configuration.auctionParams);
        // uint256 bidNumber = 0;
        // uint128 BUY_TOKEN_AMOUNT = 10000e18;

        // bytes memory txCalldata = abi.encodeCall(
        //     IContinuousClearingAuction.submitBid,
        //     (
        //         Helpers.tickNumberToPriceX96(2, params.floorPrice, params.tickSpacing), // price
        //         Helpers.inputAmountForTokens(
        //             BUY_TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2, params.floorPrice, params.tickSpacing)
        //         ),
        //         TEST_ANT_CALLER,
        //         Helpers.tickNumberToPriceX96(1, params.floorPrice, params.tickSpacing), // prev price (floor price),
        //         bytes("") // hookData
        //     )
        // );

        // console2.logBytes(txCalldata);
        // console2.log(Helpers.tickNumberToPriceX96(2, params.floorPrice, params.tickSpacing));
        // console2.log(Helpers.tickNumberToPriceX96(1, params.floorPrice, params.tickSpacing));
        // console2.log(
        //     Helpers.inputAmountForTokens(
        //         BUY_TOKEN_AMOUNT, Helpers.tickNumberToPriceX96(2, params.floorPrice, params.tickSpacing)
        //     )
        // );

        // string[] memory castParams = new string[](11);
        // params[0] = "cast";
        // params[1] = "send";
        // params[2] = "--json";
        // params[3] = vm.toString(AUCTION);
        // params[4] = vm.toString(txCalldata);
        // params[5] = '--value';
        // params[6] = vm.toString(value);
        // params[7] = "--account";
        // params[8] = vm.toString(key);
        // params[9] = "--rpc-url";
        // params[10] = rpcUrl;
        // vm.ffi(params);

        // bytes memory result = vm.rpc(
        //     "eth_sendRawTransaction",
        //     "[\"0x02f901350153018502540be400830f4240943d77edd9989be6e2f840c5ec5b3ca18358fa98aa888ac7230489e80000b8c4a52c87280000000000000000000000000000000000000000004189374bc6a7ef9db22d0e0000000000000000000000000000000000000000000000008ac7230489e80000000000000000000000000000701f7fdfabd99dfc3c0b2b226fd379d4be93dff300000000000000000000000000000000000000000020c49ba5e353f7ced9168700000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000c001a0224fcb1cbaf7b46d73b5658d7fdcb315430d00aa6078b2925eced2a04ea68008a06a3ca7b3579803b0b15d96c81103e2454e4ff2f35f3b6f584d6550e85092dba4\"]"
        // );

        // console2.logBytes(result);
    }
}
