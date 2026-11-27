// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPayable} from "./IPayer.sol";

/**
 * @title ISystemContract
 * @notice Interface to the Reactive Omni System Contract at 0x8888888888888888888888888888888888888888.
 */
interface ISystemContract is IPayable {
    struct CallbackConfiguration_V_1_0 {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external;

    function depositTo(address _contract) external payable;
}
