// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IReactive} from "../interfaces/IReactive.sol";
import {ISystemContract} from "../interfaces/ISystemContract.sol";
import {AbstractPayer} from "./AbstractPayer.sol";

/**
 * @title AbstractReactive
 * @notice Base contract for Reactive Omni contracts running on Lasna / Reactive Mainnet.
 *         Targets the native Omni System Contract at 0x8888888888888888888888888888888888888888.
 */
abstract contract AbstractReactive is IReactive, AbstractPayer {
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    ISystemContract internal constant SYSTEM =
        ISystemContract(payable(0x8888888888888888888888888888888888888888));

    error OnlySystemContract();

    constructor() {
        vendor = SYSTEM;
        addAuthorizedSender(address(SYSTEM));
    }

    modifier onlySystem() {
        if (msg.sender != address(SYSTEM)) revert OnlySystemContract();
        _;
    }
}
