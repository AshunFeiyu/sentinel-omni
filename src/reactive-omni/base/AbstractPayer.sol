// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPayable, IPayer} from "../interfaces/IPayer.sol";

/**
 * @title AbstractPayer
 * @notice Handles payment of execution debt to the Reactive System / Callback Proxy.
 */
abstract contract AbstractPayer is IPayer {
    IPayable internal vendor;
    mapping(address => bool) internal senders;

    error UnauthorizedSender();
    error InsufficientFunds();
    error TransferFailed();

    constructor() {}

    receive() external payable virtual override {}

    modifier authorizedSenderOnly() {
        if (!senders[msg.sender]) revert UnauthorizedSender();
        _;
    }

    function addAuthorizedSender(address sender_) internal {
        senders[sender_] = true;
    }

    function removeAuthorizedSender(address sender_) internal {
        senders[sender_] = false;
    }

    function pay(uint256 amount) external override authorizedSenderOnly {
        _pay(payable(msg.sender), amount);
    }

    function coverDebt() external {
        uint256 amount = vendor.debt(address(this));
        _pay(payable(address(vendor)), amount);
    }

    function _pay(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientFunds();
        if (amount > 0) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed();
        }
    }
}
