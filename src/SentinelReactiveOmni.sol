// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AbstractReactive} from "./reactive-omni/base/AbstractReactive.sol";
import {ISystemContract} from "./reactive-omni/interfaces/ISystemContract.sol";

/**
 * @title SentinelReactiveOmni
 * @notice Autonomous cross-chain DeFi Vault & Verifier Immune Engine deployed on Reactive Omni (Lasna).
 *         Correlates sub-second events across Unichain Sepolia (1301) and Base Sepolia (84532),
 *         computes deterministic composite risk scores, propagates origin timestamps for on-chain
 *         latency telemetry, proves stale-NAV / equivocation invariants, and dispatches zero-keeper
 *         callbacks via `SYSTEM.requestCallbackV_1_0`.
 */
contract SentinelReactiveOmni is AbstractReactive {
    uint256 public constant BPS = 10_000;
    uint64 public constant DEFAULT_CALLBACK_GAS_LIMIT = 850_000;

    uint256 public constant REASON_DEPEG_SHOCK = 1;
    uint256 public constant REASON_STALE_NAV_FORCE_SELL = 2;
    uint256 public constant REASON_TEE_EQUIVOCATION = 3;

    // Event signatures subscribed across origin chains
    uint256 public constant TOPIC_TX_NAV_LOCKED =
        uint256(keccak256("TxNavLocked(address,uint256,uint256,uint256)"));
    uint256 public constant TOPIC_DISTRESSED_SALE =
        uint256(keccak256("DistressedSaleExecuted(address,uint256,uint256,uint256,bool,uint256)"));
    uint256 public constant TOPIC_PRICE_SHOCK =
        uint256(keccak256("CollateralPriceShock(address,uint256,uint256,uint256,uint256)"));
    uint256 public constant TOPIC_CONFLICTING_ROOT =
        uint256(keccak256("ConflictingRootObserved(uint256,bytes32,bytes32)"));

    uint256 public immutable originVaultChainId;
    uint256 public immutable originPoolChainId;
    uint256 public immutable destinationChainId;

    address public immutable vaultAddress;
    address public immutable poolAddress;
    address public immutable disputeMonitorAddress;
    address public immutable vaultCallbackRecipient;
    address public immutable verifierCallbackRecipient;

    uint256 public immutable riskThresholdBps;
    uint256 public immutable safeReserveTargetBps;

    struct VaultRiskState {
        uint256 lastShockBps;
        uint256 lastLossBps;
        uint256 lastDispatchedLossBps;
        uint256 compositeRiskBps;
        uint256 lastOriginTimestamp;
        bool staleNavWindowArmed;
        bool circuitBreakerDispatched;
        uint256 interventions;
    }

    struct VerifierRiskState {
        bytes32 rootA;
        bytes32 rootB;
        bool equivocationProven;
        bool quarantineDispatched;
    }

    mapping(address => VaultRiskState) public vaultTelemetry;
    mapping(uint256 => VerifierRiskState) public disputeTelemetry;

    event RiskTelemetryUpdated(
        uint256 indexed originChainId,
        address indexed targetVault,
        uint256 shockBps,
        uint256 lossBps,
        uint256 compositeRiskBps,
        bool staleNavArmed,
        uint256 originTimestamp
    );
    event VaultDefenseDispatched(
        address indexed targetVault,
        uint256 indexed reasonCode,
        uint256 lossBps,
        uint256 compositeRiskBps,
        uint256 originTimestamp,
        uint256 reactiveTimestamp
    );
    event VerifierQuarantineDispatched(
        uint256 indexed gameId,
        bytes32 rootA,
        bytes32 rootB,
        uint256 reactiveTimestamp
    );

    constructor(
        uint256 originVaultChainId_,
        uint256 originPoolChainId_,
        uint256 destinationChainId_,
        address vaultAddress_,
        address poolAddress_,
        address disputeMonitorAddress_,
        address vaultCallbackRecipient_,
        address verifierCallbackRecipient_,
        uint256 riskThresholdBps_,
        uint256 safeReserveTargetBps_
    ) payable {
        originVaultChainId = originVaultChainId_;
        originPoolChainId = originPoolChainId_;
        destinationChainId = destinationChainId_;
        vaultAddress = vaultAddress_;
        poolAddress = poolAddress_;
        disputeMonitorAddress = disputeMonitorAddress_;
        vaultCallbackRecipient = vaultCallbackRecipient_;
        verifierCallbackRecipient = verifierCallbackRecipient_;
        riskThresholdBps = riskThresholdBps_;
        safeReserveTargetBps = safeReserveTargetBps_;

        _subscribeTopic(originVaultChainId_, vaultAddress_, TOPIC_TX_NAV_LOCKED);
        _subscribeTopic(originVaultChainId_, vaultAddress_, TOPIC_DISTRESSED_SALE);
        _subscribeTopic(originPoolChainId_, poolAddress_, TOPIC_PRICE_SHOCK);
        _subscribeTopic(originVaultChainId_, disputeMonitorAddress_, TOPIC_CONFLICTING_ROOT);
    }

    function react(LogRecord calldata log_) external override onlySystem {
        uint256 topic0 = log_.topic_0;

        if (topic0 == TOPIC_TX_NAV_LOCKED && log_._contract == vaultAddress) {
            _handleTxNavLocked(log_);
        } else if (topic0 == TOPIC_DISTRESSED_SALE && log_._contract == vaultAddress) {
            _handleDistressedSale(log_);
        } else if (topic0 == TOPIC_PRICE_SHOCK && log_._contract == poolAddress) {
            _handleCollateralPriceShock(log_);
        } else if (topic0 == TOPIC_CONFLICTING_ROOT && log_._contract == disputeMonitorAddress) {
            _handleConflictingRoot(log_);
        }
    }

    function _subscribeTopic(uint256 chainId_, address contract_, uint256 topic0_) internal {
        if (contract_ == address(0)) return;
        SYSTEM.subscribe(
            chainId_,
            contract_,
            topic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    function _handleTxNavLocked(LogRecord calldata log_) internal {
        address targetVault = address(uint160(log_.topic_1));
        (, , uint256 originTs) = abi.decode(log_.data, (uint256, uint256, uint256));

        VaultRiskState storage state = vaultTelemetry[targetVault];
        state.staleNavWindowArmed = true;
        state.lastOriginTimestamp = originTs;
        state.compositeRiskBps = _computeRisk(state.lastShockBps, state.lastLossBps, true);

        emit RiskTelemetryUpdated(
            log_.chain_id,
            targetVault,
            state.lastShockBps,
            state.lastLossBps,
            state.compositeRiskBps,
            true,
            originTs
        );

        if (state.compositeRiskBps >= riskThresholdBps) {
            _dispatchVaultDefense(targetVault, REASON_DEPEG_SHOCK, state, originTs);
        }
    }

    function _handleDistressedSale(LogRecord calldata log_) internal {
        address targetVault = address(uint160(log_.topic_1));
        (, , uint256 lossBps, bool staleNavLocked, uint256 originTs) =
            abi.decode(log_.data, (uint256, uint256, uint256, bool, uint256));

        VaultRiskState storage state = vaultTelemetry[targetVault];
        state.lastLossBps = lossBps;
        state.lastOriginTimestamp = originTs;
        if (staleNavLocked) {
            state.staleNavWindowArmed = true;
        }
        state.compositeRiskBps = _computeRisk(state.lastShockBps, lossBps, state.staleNavWindowArmed);

        emit RiskTelemetryUpdated(
            log_.chain_id,
            targetVault,
            state.lastShockBps,
            lossBps,
            state.compositeRiskBps,
            state.staleNavWindowArmed,
            originTs
        );

        if (state.staleNavWindowArmed && lossBps > 0) {
            _dispatchVaultDefense(targetVault, REASON_STALE_NAV_FORCE_SELL, state, originTs);
        } else if (state.compositeRiskBps >= riskThresholdBps) {
            _dispatchVaultDefense(targetVault, REASON_DEPEG_SHOCK, state, originTs);
        }
    }

    function _handleCollateralPriceShock(LogRecord calldata log_) internal {
        address targetVault = address(uint160(log_.topic_1));
        (, , uint256 shockBps, uint256 originTs) =
            abi.decode(log_.data, (uint256, uint256, uint256, uint256));

        VaultRiskState storage state = vaultTelemetry[targetVault];
        state.lastShockBps = shockBps;
        state.lastOriginTimestamp = originTs;
        state.compositeRiskBps = _computeRisk(shockBps, state.lastLossBps, state.staleNavWindowArmed);

        emit RiskTelemetryUpdated(
            log_.chain_id,
            targetVault,
            shockBps,
            state.lastLossBps,
            state.compositeRiskBps,
            state.staleNavWindowArmed,
            originTs
        );

        if (state.compositeRiskBps >= riskThresholdBps) {
            _dispatchVaultDefense(targetVault, REASON_DEPEG_SHOCK, state, originTs);
        }
    }

    function _handleConflictingRoot(LogRecord calldata log_) internal {
        uint256 gameId = log_.topic_1;
        (bytes32 rootA, bytes32 rootB) = abi.decode(log_.data, (bytes32, bytes32));
        if (rootA == rootB) return;

        VerifierRiskState storage vState = disputeTelemetry[gameId];
        vState.rootA = rootA;
        vState.rootB = rootB;
        vState.equivocationProven = true;

        if (!vState.quarantineDispatched && verifierCallbackRecipient != address(0)) {
            vState.quarantineDispatched = true;
            bytes memory payload = abi.encodeWithSignature(
                "quarantineCompromisedVerifier(address,address,uint256,bytes32,bytes32)",
                address(0),
                disputeMonitorAddress,
                gameId,
                rootA,
                rootB
            );
            _requestCallback(verifierCallbackRecipient, payload);
            emit VerifierQuarantineDispatched(gameId, rootA, rootB, block.timestamp);
        }
    }

    function _dispatchVaultDefense(
        address targetVault,
        uint256 reasonCode,
        VaultRiskState storage state,
        uint256 originTs
    ) internal {
        if (vaultCallbackRecipient == address(0)) return;

        uint256 dispatchedLossBps = state.lastLossBps;
        uint256 dispatchedRiskBps = state.compositeRiskBps;

        state.circuitBreakerDispatched = true;
        state.staleNavWindowArmed = false;
        state.lastDispatchedLossBps = dispatchedLossBps;
        state.lastLossBps = 0;
        state.lastShockBps = 0;
        state.interventions += 1;

        bytes memory breakerPayload = abi.encodeWithSignature(
            "triggerEmergencyCircuitBreaker(address,address,uint256,uint256,uint256,uint256,uint256)",
            address(0),
            targetVault,
            reasonCode,
            dispatchedLossBps,
            dispatchedRiskBps,
            originTs,
            block.timestamp
        );
        _requestCallback(vaultCallbackRecipient, breakerPayload);

        bytes memory rebalancePayload = abi.encodeWithSignature(
            "executeSelfHealingRebalance(address,address,uint256,uint256)",
            address(0),
            targetVault,
            safeReserveTargetBps,
            originTs
        );
        _requestCallback(vaultCallbackRecipient, rebalancePayload);

        emit VaultDefenseDispatched(
            targetVault,
            reasonCode,
            dispatchedLossBps,
            dispatchedRiskBps,
            originTs,
            block.timestamp
        );
    }

    function _requestCallback(address recipient, bytes memory payload) internal {
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: recipient,
                gasLimit: DEFAULT_CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    function _computeRisk(
        uint256 shockBps,
        uint256 lossBps,
        bool staleNavArmed
    ) internal pure returns (uint256 score) {
        score = lossBps + ((shockBps * 80) / 100) + (staleNavArmed ? 2_500 : 0);
        if (score > BPS) score = BPS;
    }

    function getVaultTelemetry(address vault_) external view returns (VaultRiskState memory) {
        return vaultTelemetry[vault_];
    }

    function getDisputeTelemetry(uint256 gameId_) external view returns (VerifierRiskState memory) {
        return disputeTelemetry[gameId_];
    }
}
