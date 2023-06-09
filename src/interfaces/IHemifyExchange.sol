// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
* @title IHemifyExchange
* @author fps (@0xfps).
* @custom:version 1.0.0
* @dev Interface controlling `HemifyExchange`.
*/

interface IHemifyExchange {
    /// @dev Emitted on every successful swap.
    /// @param token        IERC20 token.
    /// @param amountIn     Amount of token sent.
    /// @param amountOut    Amount of ETH taken out.
    event Swap(IERC20 token, uint256 amountIn, uint256 amountOut);

    error NotAllowedToken();
    error NotSwapped();

    /**
    * @dev Swaps token(`USDC` or `USDT`) for ETH. Any resulting ETH is sent to `from`.
    * @param from     Swapper.
    * @param token    Token(`USDC` or `USDT`).
    * @param amount   Amount of tokens to be swapped.
    * @return bool    Swap status.
    */
    function swapToETH(address from, IERC20 token, uint256 amount) external returns (bool);
}