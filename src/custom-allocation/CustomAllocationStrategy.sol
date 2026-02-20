// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDistributionStrategy} from "liquidity-launcher/src/interfaces/IDistributionStrategy.sol";
import {IDistributionContract} from "liquidity-launcher/src/interfaces/IDistributionContract.sol";

import {ICustomAllocationStrategy} from "../interfaces/ICustomAllocationStrategy.sol";

contract CustomAllocationStrategy is ICustomAllocationStrategy {
    using SafeERC20 for IERC20;

    /// @notice Maximum value for token split percentage (100% in basis points)
    /// @dev 1e7 = 10,000,000 basis points = 100%
    uint24 internal constant _MAX_TOKEN_SPLIT = 1e7;

    /// @notice The maximum allocation split percentage i.e. 50%
    uint24 internal constant _MAX_ALLOCATION_SPLIT = 5e6;

    /// @notice The address of the LiquidityLauncher contract
    address internal immutable _LIQUIDITY_LAUNCHER;

    /// @notice The parameters for the each custom allocation
    Parameters internal _parameters;

    constructor(address liquidityLauncher) {
        _LIQUIDITY_LAUNCHER = liquidityLauncher;
    }

    modifier onlyLiquidityLauncher() {
        require(msg.sender == _LIQUIDITY_LAUNCHER, OnlyLiquidityLauncher());
        _;
    }

    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32)
        external
        onlyLiquidityLauncher
        returns (IDistributionContract)
    {
        uint256 maxAllocationAmount = IERC20(token).totalSupply() * _MAX_ALLOCATION_SPLIT / _MAX_TOKEN_SPLIT;
        require(amount <= maxAllocationAmount, AllocationSplitTooHigh(amount, maxAllocationAmount));

        (address recipient) = abi.decode(configData, (address));
        require(recipient != address(0), InvalidRecipient());

        // Store parameters transiently for distribution contract to access during `onTokensReceived`
        _parameters = Parameters({tokenAddress: token, allocationRecipient: recipient, allocationAmount: amount});

        return IDistributionContract(address(this));
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external onlyLiquidityLauncher {
        Parameters memory params = _parameters;
        uint256 tokenBalance = IERC20(params.tokenAddress).balanceOf(address(this));
        require(tokenBalance == params.allocationAmount, InvalidAmountReceived(params.allocationAmount, tokenBalance));

        IERC20(params.tokenAddress).safeTransfer(params.allocationRecipient, params.allocationAmount);

        emit TokensAllocated(params.tokenAddress, params.allocationRecipient, params.allocationAmount);

        // Clear parameters after each distribution
        delete _parameters;
    }
}
