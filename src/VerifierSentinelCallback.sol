// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPayable} from "./reactive-omni/interfaces/IPayer.sol";
import {AbstractCallback} from "./reactive-omni/base/AbstractCallback.sol";
import {DualProofDisputeMonitor} from "./DualProofDisputeMonitor.sol";

/**
 * @title VerifierSentinelCallback
 * @notice Destination callback receiver enforcing cross-chain TEE equivocation quarantine
 *         even when L1 `AggregateVerifier.nullify()` is blocked by `challenge()` front-running.
 */
contract VerifierSentinelCallback is AbstractCallback {
    address public immutable owner;
    uint256 public quarantinesExecuted;

    event VerifierQuarantineApplied(
        address indexed reactiveSender,
        address indexed monitor,
        uint256 indexed gameId,
        bytes32 rootA,
        bytes32 rootB
    );

    error OnlyOwner();
    error SenderAlreadyBound();

    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        owner = msg.sender;
    }

    function bindReactiveSender(address reactiveSender_) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (callbackSender != address(0)) revert SenderAlreadyBound();
        callbackSender = reactiveSender_;
    }

    function quarantineCompromisedVerifier(
        address reactive_,
        address monitor_,
        uint256 gameId_,
        bytes32 rootA_,
        bytes32 rootB_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        quarantinesExecuted += 1;
        DualProofDisputeMonitor(monitor_).quarantineTeeFromReactive(gameId_, rootA_, rootB_);
        emit VerifierQuarantineApplied(reactive_, monitor_, gameId_, rootA_, rootB_);
    }
}
