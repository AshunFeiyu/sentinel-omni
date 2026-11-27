// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IPayable
 * @notice Minimal Reactive Omni payable service interface for callback proxy / system debt settlement.
 */
interface IPayable {
    receive() external payable;

    function debt(address _contract) external view returns (uint256);
}

/**
 * @title IPayer
 * @notice Interface implemented by Reactive and Callback contracts to settle execution debt.
 */
interface IPayer {
    receive() external payable;

    function pay(uint256 amount) external;
}
