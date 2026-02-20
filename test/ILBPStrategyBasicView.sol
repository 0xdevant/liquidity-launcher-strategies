// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILBPStrategyBasicView {
    function token() external view returns (address);
    function currency() external view returns (address);
    function totalSupply() external view returns (uint128);
    function reserveSupply() external view returns (uint128);
    function positionRecipient() external view returns (address);
    function migrationBlock() external view returns (uint64);

    function positionManager() external view returns (address);
    function poolManager() external view returns (address);
    function poolLPFee() external view returns (uint24);
    function poolTickSpacing() external view returns (int24);
    function auctionParameters() external view returns (bytes memory);
}
