// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// e this is probably the interface to work with poolfactory.sol from tswap
// follow up why are we using tswap? what does thst have to do with flash loans?
// a we need it to get he value of a token to caluclate fees
interface IPoolFactory {
    function getPool(address tokenAddress) external view returns (address);
}
