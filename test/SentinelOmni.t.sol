// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IPayable} from "../src/reactive-omni/interfaces/IPayer.sol";
import {IReactive} from "../src/reactive-omni/interfaces/IReactive.sol";
import {SafeHavenReserve} from "../src/SafeHavenReserve.sol";
import {ProtectedCreditVault} from "../src/ProtectedCreditVault.sol";
import {MockDepegPool} from "../src/MockDepegPool.sol";
import {DualProofDisputeMonitor} from "../src/DualProofDisputeMonitor.sol";
import {VaultSentinelCallback} from "../src/VaultSentinelCallback.sol";
import {VerifierSentinelCallback} from "../src/VerifierSentinelCallback.sol";
import {SentinelReactiveOmni} from "../src/SentinelReactiveOmni.sol";
import {MockCallbackProxy, MockSystemContract} from "./mocks/MockReactiveOmniInfra.sol";

contract SentinelOmniTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant UNICHAIN_SEPOLIA_CHAIN_ID = 1301;

    MockSystemContract internal sys;
    MockCallbackProxy internal proxy;

    SafeHavenReserve internal safeHaven;
    ProtectedCreditVault internal vault;
    MockDepegPool internal pool;
    DualProofDisputeMonitor internal disputeMonitor;

    VaultSentinelCallback internal vaultCallback;
    VerifierSentinelCallback internal verifierCallback;
    SentinelReactiveOmni internal sentinel;

    address internal attacker = address(0xA11AC);
    address internal victim = address(0xB0B0);

    function setUp() public {
        vm.warp(1_795_000_000);
        MockSystemContract impl = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        sys = MockSystemContract(payable(SYSTEM_ADDR));

        proxy = new MockCallbackProxy();

        safeHaven = new SafeHavenReserve();
        vault = new ProtectedCreditVault(true);
        pool = new MockDepegPool();
        disputeMonitor = new DualProofDisputeMonitor();

        vaultCallback = new VaultSentinelCallback(IPayable(payable(address(proxy))), address(0));
        verifierCallback = new VerifierSentinelCallback(IPayable(payable(address(proxy))), address(0));

        sentinel = new SentinelReactiveOmni{value: 1 ether}(
            BASE_SEPOLIA_CHAIN_ID,
            UNICHAIN_SEPOLIA_CHAIN_ID,
            BASE_SEPOLIA_CHAIN_ID,
            address(vault),
            address(pool),
            address(disputeMonitor),
            address(vaultCallback),
            address(verifierCallback),
            7_000,
            8_000
        );

        vaultCallback.bindReactiveSender(address(sentinel));
        verifierCallback.bindReactiveSender(address(sentinel));
        vault.setSafeHaven(safeHaven);
        vault.setSentinelCallback(address(vaultCallback));
        disputeMonitor.setVerifierSentinelCallback(address(verifierCallback));
    }

    /// @dev Simulates 1s Reactive Omni CometBFT finality + 1s Base Sepolia Denim callback inclusion.
    function _relayCapturedLogs(Vm.Log[] memory logs, uint256 originChainId) internal {
        vm.warp(block.timestamp + 1);
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.topics.length == 0) continue;

            IReactive.LogRecord memory rec = IReactive.LogRecord({
                chain_id: originChainId,
                _contract: entry.emitter,
                topic_0: uint256(entry.topics[0]),
                topic_1: entry.topics.length > 1 ? uint256(entry.topics[1]) : 0,
                topic_2: entry.topics.length > 2 ? uint256(entry.topics[2]) : 0,
                topic_3: entry.topics.length > 3 ? uint256(entry.topics[3]) : 0,
                data: entry.data,
                block_number: block.number,
                op_code: 0,
                block_hash: uint256(blockhash(block.number - 1)),
                tx_hash: uint256(keccak256(abi.encode(i, block.timestamp))),
                log_index: i
            });
            sys.dispatchLogToSubscribers(rec);
        }
        vm.warp(block.timestamp + 1);
        sys.executePendingCallbacks(proxy);
    }

    function test_baselineWithoutSentinel_staleNavDrainsRemainingLp() public {
        ProtectedCreditVault legacyVault = new ProtectedCreditVault(false);

        legacyVault.depositAllocated(attacker, 50_000e6);
        legacyVault.depositAllocated(victim, 50_000e6);
        assertEq(legacyVault.idleCash(), 0);

        legacyVault.beginTxNavLock();
        legacyVault.executeDistressedSale(5_000);
        uint256 attackerOut = legacyVault.redeem(attacker, 50_000e6);
        legacyVault.endTxNavLock();

        assertEq(attackerOut, 50_000e6);
        assertEq(legacyVault.trueTotalAssets(), 0);

        uint256 victimOut = legacyVault.redeem(victim, 50_000e6);
        assertEq(victimOut, 0);
    }

    function test_withSentinel_distressedSaleTriggersReactiveBreakerSafeHavenAndLatency() public {
        vault.depositAllocated(attacker, 50_000e6);
        vault.depositAllocated(victim, 50_000e6);

        vm.recordLogs();
        vault.beginTxNavLock();
        vault.executeDistressedSale(5_000);
        Vm.Log[] memory originLogs = vm.getRecordedLogs();

        vm.expectRevert(ProtectedCreditVault.StaleNavRedemptionBlocked.selector);
        vault.redeem(attacker, 50_000e6);

        _relayCapturedLogs(originLogs, BASE_SEPOLIA_CHAIN_ID);

        assertTrue(vault.circuitBreakerActive());
        assertEq(vault.firstTotalAssets(), 0);
        // 80% of 50,000e6 = 40,000e6 migrated into external SafeHavenReserve
        assertEq(vault.safeReserveCash(), 40_000e6);
        assertEq(safeHaven.reservedBalanceOf(address(vault)), 40_000e6);
        assertEq(vault.idleCash(), 10_000e6);

        // Verified on-chain sub-second / 2-second end-to-end reaction telemetry
        assertEq(vaultCallback.lastTotalLatencySec(), 2);
        assertEq(vaultCallback.lastRelayLatencySec(), 1);

        SentinelReactiveOmni.VaultRiskState memory telemetry = sentinel.getVaultTelemetry(address(vault));
        assertTrue(telemetry.circuitBreakerDispatched);
        assertEq(telemetry.lastDispatchedLossBps, 5_000);
        assertEq(telemetry.compositeRiskBps, 7_500);

        // Pro-rata settlement pulls smoothly from SafeHavenReserve as needed
        uint256 attackerOut = vault.redeem(attacker, 50_000e6);
        uint256 victimOut = vault.redeem(victim, 50_000e6);

        assertEq(attackerOut, 25_000e6);
        assertEq(victimOut, 25_000e6);
        assertEq(safeHaven.reservedBalanceOf(address(vault)), 0);
        assertEq(vault.trueTotalAssets(), 0);
    }

    function test_crossChainUnichainDepeg_preemptivelyArmsVaultDefense() public {
        vault.depositAllocated(attacker, 50_000e6);
        vault.depositAllocated(victim, 50_000e6);

        vm.recordLogs();
        pool.reportSwapPrice(address(vault), 0.40e18);
        _relayCapturedLogs(vm.getRecordedLogs(), UNICHAIN_SEPOLIA_CHAIN_ID);
        assertFalse(vault.circuitBreakerActive());

        vm.recordLogs();
        vault.beginTxNavLock();
        _relayCapturedLogs(vm.getRecordedLogs(), BASE_SEPOLIA_CHAIN_ID);

        assertTrue(vault.circuitBreakerActive());
        assertEq(vault.firstTotalAssets(), 0);
        assertEq(vaultCallback.interventionsExecuted(), 2);
        assertEq(vaultCallback.lastTotalLatencySec(), 2);
    }

    function test_dualProofVerifier_challengeBlocksLegacyNullify_reactiveQuarantinesTee() public {
        uint256 gameId = 621;
        bytes32 fakeTeeRoot = keccak256("FRAUDULENT_TEE_STATE_ROOT");
        bytes32 canonicalRoot = keccak256("CANONICAL_ZK_STATE_ROOT");

        disputeMonitor.proposeGame(gameId, fakeTeeRoot, true);

        vm.recordLogs();
        disputeMonitor.challengeGame(gameId, canonicalRoot);
        Vm.Log[] memory challengeLogs = vm.getRecordedLogs();

        vm.expectRevert(DualProofDisputeMonitor.TeeNullifyBlockedAfterChallenge.selector);
        disputeMonitor.legacyNullifyTee(gameId, canonicalRoot);
        assertTrue(disputeMonitor.teeTrusted());
        assertEq(disputeMonitor.finalizationDelay(), 1 days);

        _relayCapturedLogs(challengeLogs, BASE_SEPOLIA_CHAIN_ID);

        assertFalse(disputeMonitor.teeTrusted());
        assertEq(disputeMonitor.finalizationDelay(), 5 days);
        assertTrue(disputeMonitor.fastBridgePaused());
        assertEq(verifierCallback.quarantinesExecuted(), 1);
    }

    function test_securityBoundaries_unauthorizedSystemAndSpoofedCallbackRevert() public {
        IReactive.LogRecord memory dummyLog = IReactive.LogRecord({
            chain_id: BASE_SEPOLIA_CHAIN_ID,
            _contract: address(vault),
            topic_0: sentinel.TOPIC_TX_NAV_LOCKED(),
            topic_1: uint256(uint160(address(vault))),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(uint256(100), uint256(100), block.timestamp),
            block_number: 1,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        vm.expectRevert(bytes4(keccak256("OnlySystemContract()")));
        sentinel.react(dummyLog);

        vm.expectRevert(bytes4(keccak256("OnlyServiceProvider()")));
        vaultCallback.triggerEmergencyCircuitBreaker(
            address(sentinel), address(vault), 1, 5_000, 8_000, block.timestamp, block.timestamp
        );

        vm.prank(address(proxy));
        vm.expectRevert(bytes4(keccak256("OnlyAuthorizedReactiveSender()")));
        vaultCallback.triggerEmergencyCircuitBreaker(
            attacker, address(vault), 1, 5_000, 8_000, block.timestamp, block.timestamp
        );
    }

    function testFuzz_proRataSolvencyPreserved(
        uint96 attackerDeposit,
        uint96 victimDeposit,
        uint16 recoveryBps
    ) public {
        uint256 aDep = bound(attackerDeposit, 1e6, 1_000_000e6);
        uint256 vDep = bound(victimDeposit, 1e6, 1_000_000e6);
        uint256 recBps = bound(recoveryBps, 100, 9_900);

        vault.depositAllocated(attacker, aDep);
        vault.depositAllocated(victim, vDep);

        vm.recordLogs();
        vault.beginTxNavLock();
        vault.executeDistressedSale(recBps);
        _relayCapturedLogs(vm.getRecordedLogs(), BASE_SEPOLIA_CHAIN_ID);

        uint256 totalRecovered = vault.trueTotalAssets();
        uint256 totalShares = vault.totalShares();
        uint256 expectedVictimFair = (vDep * totalRecovered) / totalShares;

        vault.redeem(attacker, aDep);
        uint256 actualVictimOut = vault.redeem(victim, vDep);

        assertGe(actualVictimOut, expectedVictimFair);
        assertLe(actualVictimOut - expectedVictimFair, 1);
    }

    function test_repeatedDistressedWaves_alwaysDispatchSelfHealing() public {
        vault.depositAllocated(attacker, 40_000e6);
        vault.depositAllocated(victim, 60_000e6);

        vm.recordLogs();
        vault.beginTxNavLock();
        vault.executeDistressedSale(5_000);
        _relayCapturedLogs(vm.getRecordedLogs(), BASE_SEPOLIA_CHAIN_ID);
        assertEq(vault.firstTotalAssets(), 0);

        vault.depositAllocated(victim, 20_000e6);
        vm.recordLogs();
        vault.beginTxNavLock();
        vault.executeDistressedSale(5_000);
        _relayCapturedLogs(vm.getRecordedLogs(), BASE_SEPOLIA_CHAIN_ID);

        assertEq(vault.firstTotalAssets(), 0);
        assertEq(sentinel.getVaultTelemetry(address(vault)).interventions, 2);
    }
}
