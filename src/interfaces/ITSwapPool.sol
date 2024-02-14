// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// follow up why do we need the price of this token in weth?
interface ITSwapPool {
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
