// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPayer} from "./IPayer.sol";

/**
 * @title IReactive
 * @notice Reactive Omni interface matching `Reactive-Network/reactive-lib-omni`.
 */
interface IReactive is IPayer {
    struct LogRecord {
        uint256 chain_id;
        address _contract;
        uint256 topic_0;
        uint256 topic_1;
        uint256 topic_2;
        uint256 topic_3;
        bytes data;
        uint256 block_number;
        uint256 op_code;
        uint256 block_hash;
        uint256 tx_hash;
        uint256 log_index;
    }

    function react(LogRecord calldata log_) external;
}
