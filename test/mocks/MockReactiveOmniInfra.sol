// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IReactive} from "../../src/reactive-omni/interfaces/IReactive.sol";
import {ISystemContract} from "../../src/reactive-omni/interfaces/ISystemContract.sol";

/**
 * @title MockCallbackProxy
 * @notice Simulates the Base Sepolia / Unichain Omni Callback Proxy, including
 *         overwriting payload slot 0 (first ABI argument) with the calling Reactive address.
 */
contract MockCallbackProxy {
    mapping(address => uint256) public debts;

    event CallbackRelayed(
        address indexed reactiveSender,
        address indexed recipient,
        uint256 chainId,
        uint64 gasLimit,
        bool success
    );

    error CallbackExecutionFailed(bytes revertData);

    receive() external payable {}

    function debt(address _contract) external view returns (uint256) {
        return debts[_contract];
    }

    function relay(
        address reactiveSender_,
        uint256 chainId_,
        address recipient_,
        uint64 gasLimit_,
        bytes memory payload_
    ) external returns (bytes memory ret) {
        // Mimic Reactive Network security guarantee: overwrite first 32-byte slot (selector + 32 bytes)
        // with the authenticated originating Reactive Contract address.
        require(payload_.length >= 36, "Payload too short for slot0 injection");
        bytes memory patched = bytes.concat(payload_);
        assembly {
            mstore(add(patched, 36), reactiveSender_)
        }

        (bool ok, bytes memory data) = recipient_.call{gas: gasLimit_}(patched);
        emit CallbackRelayed(reactiveSender_, recipient_, chainId_, gasLimit_, ok);
        if (!ok) revert CallbackExecutionFailed(data);
        return data;
    }
}

/**
 * @title MockSystemContract
 * @notice Deployed at 0x8888888888888888888888888888888888888888 via `vm.etch` in tests.
 *         Tracks subscriptions, delivers logs to `react()`, and queues/dispatches V1.0 callbacks.
 */
contract MockSystemContract is ISystemContract {
    struct Subscription {
        address subscriber;
        uint256 chainId;
        address targetContract;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    struct QueuedCallback {
        address reactiveSender;
        CallbackConfiguration_V_1_0 config;
        bool executed;
    }

    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    Subscription[] public subscriptions;
    QueuedCallback[] public queuedCallbacks;
    mapping(address => uint256) public debts;

    event Subscribed(address indexed subscriber, uint256 indexed chainId, address indexed target, uint256 topic0);
    event CallbackRequested(address indexed reactiveSender, uint256 indexed chainId, address indexed recipient);

    receive() external payable {}

    function debt(address _contract) external view override returns (uint256) {
        return debts[_contract];
    }

    function depositTo(address) external payable override {}

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external override {
        subscriptions.push(
            Subscription({
                subscriber: msg.sender,
                chainId: chainId_,
                targetContract: contract_,
                topic0: topic0_,
                topic1: topic1_,
                topic2: topic2_,
                topic3: topic3_
            })
        );
        emit Subscribed(msg.sender, chainId_, contract_, topic0_);
    }

    function unsubscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external override {}

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external override {
        queuedCallbacks.push(
            QueuedCallback({
                reactiveSender: msg.sender,
                config: config_,
                executed: false
            })
        );
        emit CallbackRequested(msg.sender, config_.chainId, config_.recipient);
    }

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function queuedCallbackCount() external view returns (uint256) {
        return queuedCallbacks.length;
    }

    function dispatchLogToSubscribers(IReactive.LogRecord memory log_) external returns (uint256 matched) {
        uint256 len = subscriptions.length;
        for (uint256 i = 0; i < len; ++i) {
            Subscription memory sub = subscriptions[i];
            if (sub.chainId != log_.chain_id) continue;
            if (sub.targetContract != address(0) && sub.targetContract != log_._contract) continue;
            if (sub.topic0 != REACTIVE_IGNORE && sub.topic0 != log_.topic_0) continue;
            if (sub.topic1 != REACTIVE_IGNORE && sub.topic1 != log_.topic_1) continue;
            if (sub.topic2 != REACTIVE_IGNORE && sub.topic2 != log_.topic_2) continue;
            if (sub.topic3 != REACTIVE_IGNORE && sub.topic3 != log_.topic_3) continue;

            IReactive(payable(sub.subscriber)).react(log_);
            matched += 1;
        }
    }

    function executePendingCallbacks(MockCallbackProxy proxy_) external returns (uint256 executedCount) {
        uint256 len = queuedCallbacks.length;
        for (uint256 i = 0; i < len; ++i) {
            QueuedCallback storage q = queuedCallbacks[i];
            if (q.executed) continue;
            q.executed = true;
            proxy_.relay(
                q.reactiveSender,
                q.config.chainId,
                q.config.recipient,
                q.config.gasLimit,
                q.config.payload
            );
            executedCount += 1;
        }
    }
}
