// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPayable} from "./reactive-omni/interfaces/IPayer.sol";
import {AbstractCallback} from "./reactive-omni/base/AbstractCallback.sol";
import {ProtectedCreditVault} from "./ProtectedCreditVault.sol";

/**
 * @title VaultSentinelCallback
 * @notice Base Sepolia (84532) callback receiver authenticated by Reactive Omni Callback Proxy
 *         and the authorized `SentinelReactiveOmni` address in payload slot 0.
 *         Tracks verified on-chain end-to-end reaction latency (`Every Second Counts` telemetry).
 */
contract VaultSentinelCallback is AbstractCallback {
    address public immutable owner;
    uint256 public interventionsExecuted;
    uint256 public lastTotalLatencySec;
    uint256 public lastRelayLatencySec;
    uint256 public maxRecordedLatencySec;

    event VaultProtectionApplied(
        address indexed reactiveSender,
        address indexed vault,
        uint256 reasonCode,
        uint256 lossBps,
        uint256 riskScoreBps,
        uint256 totalLatencySec,
        uint256 relayLatencySec
    );
    event VaultRebalanceApplied(
        address indexed reactiveSender,
        address indexed vault,
        uint256 targetReserveBps,
        uint256 totalLatencySec
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

    function triggerEmergencyCircuitBreaker(
        address reactive_,
        address vault_,
        uint256 reasonCode_,
        uint256 realizedLossBps_,
        uint256 riskScoreBps_,
        uint256 originTimestamp_,
        uint256 reactiveTimestamp_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        interventionsExecuted += 1;
        uint256 totalLat = block.timestamp >= originTimestamp_ ? block.timestamp - originTimestamp_ : 0;
        uint256 relayLat = block.timestamp >= reactiveTimestamp_ ? block.timestamp - reactiveTimestamp_ : 0;
        lastTotalLatencySec = totalLat;
        lastRelayLatencySec = relayLat;
        if (totalLat > maxRecordedLatencySec) {
            maxRecordedLatencySec = totalLat;
        }

        ProtectedCreditVault(vault_).engageCircuitBreakerAndSync(
            reasonCode_,
            realizedLossBps_,
            originTimestamp_
        );
        emit VaultProtectionApplied(
            reactive_,
            vault_,
            reasonCode_,
            realizedLossBps_,
            riskScoreBps_,
            totalLat,
            relayLat
        );
    }

    function executeSelfHealingRebalance(
        address reactive_,
        address vault_,
        uint256 targetReserveBps_,
        uint256 originTimestamp_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        interventionsExecuted += 1;
        uint256 totalLat = block.timestamp >= originTimestamp_ ? block.timestamp - originTimestamp_ : 0;
        ProtectedCreditVault(vault_).isolateSafeReserve(targetReserveBps_, originTimestamp_);
        emit VaultRebalanceApplied(reactive_, vault_, targetReserveBps_, totalLat);
    }
}
