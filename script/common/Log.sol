// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    IContinuousClearingAuction,
    ICheckpointStorage,
    AuctionParameters
} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";

import {LBPStrategyBasic} from "liquidity-launcher/src/distributionContracts/LBPStrategyBasic.sol";

abstract contract Log is Test {
    function recordDeployment(address deployedAddress, string memory extraInfo) public {
        string memory md = string.concat("## ", extraInfo, " Deployment on chainId ", vm.toString(block.chainid), "\n");
        string memory table = string.concat("| Contract Name | Address |\n| --- | --- |\n");
        table = string.concat(table, string.concat("| ", extraInfo, " | ", vm.toString(deployedAddress), " |\n"));
        md = string.concat(md, table);
        vm.writeFile(string.concat("deployments/", extraInfo, ".md"), md);
    }

    function recordDeployment(address precomputedAddress, address deployedLbp, string memory extraInfo) public {
        string memory md = string.concat("## ", extraInfo, " Deployment on chainId ", vm.toString(block.chainid), "\n");
        string memory table = string.concat("| Contract Name | Address |\n| --- | --- |\n");
        table = string.concat(table, string.concat("| UERC20 Token | ", vm.toString(precomputedAddress), " |\n"));
        table = string.concat(table, string.concat("| LBPStrategyBasic | ", vm.toString(deployedLbp), " |\n"));
        table = string.concat(
            table,
            string.concat(
                "| Auction | ", vm.toString(address(LBPStrategyBasic(payable(address(deployedLbp))).auction())), " |\n"
            )
        );
        md = string.concat(md, table);
        vm.writeFile(string.concat("deployments/", vm.toString(block.chainid), ".md"), md);
    }

    function logPriceAndCurrencyRaised(IContinuousClearingAuction auction) internal {
        // get latest clearing price
        auction.checkpoint();
        uint256 latestClearingPrice = ICheckpointStorage(address(auction)).clearingPrice();
        uint256 latestCurrencyRaised = auction.currencyRaised();

        emit log_named_uint("Latest clearingPrice in Q96", latestClearingPrice);
        emit log_named_decimal_uint("Latest currencyRaised", latestCurrencyRaised, 18);
    }

    function logAuctionConfigs(IContinuousClearingAuction auction, bytes memory params) internal {
        AuctionParameters memory auctionParams = abi.decode(params, (AuctionParameters));

        emit log_named_uint("Auction start block", auction.startBlock());
        emit log_named_uint("Auction end block", auction.endBlock());
        emit log_named_decimal_uint("Auction total supply", auction.totalSupply(), 18);
        emit log_named_decimal_uint("Auction required currency raised", auctionParams.requiredCurrencyRaised, 18);
        emit log_named_uint("Auction floor price in Q96", auctionParams.floorPrice);
        emit log_string("\n");
    }
}
