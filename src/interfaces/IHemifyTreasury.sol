// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
* @title IHemifyTreasury
* @author fps (@0xfps).
* @custom:version 1.0.0
* @dev  HemifyTreasury contract interface.
*       This interface controls the `HemifyTreasury` contract.
*       `HemifyTreasury` holds ETH and tokens over the course of the auction.
*       Also, it's a general treasury. Withdrawals are guarded by a multi sig.
*/

interface IHemifyTreasury {
    /// @dev Events for different actions.
    /// @param amount   Amount deposited.
    event ETHDeposit(uint256 indexed amount);
    /// @param to       Receiver.
    /// @param amount   Amount sent.
    event ETHTransfer(address indexed to, uint256 indexed amount);

    /// @param token    IERC20 token deposited.
    /// @param amount   Amount deposited.
    event TokenDeposit(IERC20 indexed token, uint256 indexed amount);
    /// @param token    IERC20 token sent.
    /// @param to       Receiver.
    /// @param amount   Amount sent.
    event TokenTransfer(
        IERC20 indexed token,
        address indexed to,
        uint256 indexed amount
    );

    /// @param amount   Amount withdrawn.
    event ETHWithdraw(uint256 indexed amount);
    /// @param token    IERC20 token withdrawn.
    /// @param amount   Amount withdrawn.
    event TokenWithdraw(IERC20 indexed token, uint256 indexed amount);

    error LowBalance();
    error NotSent();
    error TokenAlreadyOwned();

    /// @dev Deposits ETH into the treasury.
    function deposit() external payable returns (bool);

    /// @dev Sends `amount` amount of ETH to `to`.
    function sendPayment(address to, uint256 amount) external returns (bool);

    /// @dev Sends all available balance to deployer.
    /// @notice Only callable by owner after multi sig.
    function withdraw() external returns (bool);

    /// @dev Deposits `amount` amount of token `token` from `from` into the treasury.
    function deposit(
        address from,
        IERC20 token,
        uint256 amount
    ) external returns (bool);

    /// @dev Sends `amount` amount of token `token` to `to`.
    function sendPayment(
        IERC20 token,
        address to,
        uint256 amount
    ) external returns (bool);

    /// @dev Withdraws `amount` amount of token `token` to deployer.
    /// @notice Only callable by owner after multi sig.
    function withdraw(IERC20 token, uint256 amount) external returns (bool);
}
