// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPayable} from "../interfaces/IPayer.sol";
import {AbstractPayer} from "./AbstractPayer.sol";

/**
 * @title AbstractCallback
 * @notice Destination-chain base contract authenticating Reactive Omni Callback Proxy calls
 *         and the originating Reactive Contract address injected into payload slot 0.
 */
abstract contract AbstractCallback is AbstractPayer {
    address public immutable callbackProxy;
    address public callbackSender;

    error OnlyServiceProvider();
    error OnlyAuthorizedReactiveSender();

    constructor(IPayable callbackProxy_, address callbackSender_) payable {
        vendor = callbackProxy_;
        callbackProxy = address(callbackProxy_);
        callbackSender = callbackSender_;
        addAuthorizedSender(address(callbackProxy_));
    }

    modifier onlyServiceProvider() {
        if (msg.sender != callbackProxy) revert OnlyServiceProvider();
        _;
    }

    modifier onlyCallbackSender(address reactive_) {
        if (reactive_ == address(0) || reactive_ != callbackSender) {
            revert OnlyAuthorizedReactiveSender();
        }
        _;
    }
}
