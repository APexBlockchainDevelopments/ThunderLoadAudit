// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// follow up why do we need the price of this token in weth?
// a wes shouldn't be, this is a bug
interface ITSwapPool {
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
