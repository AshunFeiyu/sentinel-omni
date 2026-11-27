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

contract SentinelInvariantHandler is Test {
    uint256 internal constant BASE_SEPOLIA = 84532;
    uint256 internal constant UNICHAIN_SEPOLIA = 1301;

    MockSystemContract public sys;
    MockCallbackProxy public proxy;
    ProtectedCreditVault public vault;
    MockDepegPool public pool;
    DualProofDisputeMonitor public monitor;
    SentinelReactiveOmni public sentinel;

    address public constant LP_A = address(0x1001);
    address public constant LP_B = address(0x1002);

    bool public equivocationOccurred;

    constructor(
        MockSystemContract sys_,
        MockCallbackProxy proxy_,
        ProtectedCreditVault vault_,
        MockDepegPool pool_,
        DualProofDisputeMonitor monitor_,
        SentinelReactiveOmni sentinel_
    ) {
        sys = sys_;
        proxy = proxy_;
        vault = vault_;
        pool = pool_;
        monitor = monitor_;
        sentinel = sentinel_;
    }

    function actionDeposit(bool isA, uint96 rawAmount) external {
        uint256 amt = bound(rawAmount, 1e6, 100_000e6);
        vault.depositAllocated(isA ? LP_A : LP_B, amt);
    }

    function actionUnichainDepeg(uint256 rawPrice) external {
        uint256 price = bound(rawPrice, 0.2e18, 1.0e18);
        vm.recordLogs();
        pool.reportSwapPrice(address(vault), price);
        _relay(vm.getRecordedLogs(), UNICHAIN_SEPOLIA);
    }

    function actionLockAndDistressedSale(uint16 recoveryBps) external {
        if (vault.creditBookValue() == 0) return;
        uint256 rec = bound(recoveryBps, 200, 9_500);
        vm.recordLogs();
        vault.beginTxNavLock();
        vault.executeDistressedSale(rec);
        _relay(vm.getRecordedLogs(), BASE_SEPOLIA);
    }

    function actionRedeem(bool isA, uint256 fractionBps) external {
        address user = isA ? LP_A : LP_B;
        uint256 bal = vault.sharesOf(user);
        if (bal == 0 || vault.totalShares() == 0) return;
        uint256 shares = (bal * bound(fractionBps, 100, 10_000)) / 10_000;
        if (shares == 0) return;

        uint256 assetsOutNeeded = (shares * vault.trueTotalAssets()) / vault.totalShares();
        if (assetsOutNeeded > vault.idleCash() + vault.safeReserveCash()) return;

        vault.redeem(user, shares);
    }

    function actionEquivocate(uint256 gameId) external {
        uint256 gid = bound(gameId, 1, 16);
        bytes32 r1 = keccak256(abi.encodePacked("TEE", gid));
        bytes32 r2 = keccak256(abi.encodePacked("ZK", gid));
        vm.recordLogs();
        monitor.proposeGame(gid, r1, true);
        monitor.challengeGame(gid, r2);
        equivocationOccurred = true;
        _relay(vm.getRecordedLogs(), BASE_SEPOLIA);
    }

    function _relay(Vm.Log[] memory logs, uint256 originChain) internal {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            IReactive.LogRecord memory rec = IReactive.LogRecord({
                chain_id: originChain,
                _contract: logs[i].emitter,
                topic_0: uint256(logs[i].topics[0]),
                topic_1: logs[i].topics.length > 1 ? uint256(logs[i].topics[1]) : 0,
                topic_2: logs[i].topics.length > 2 ? uint256(logs[i].topics[2]) : 0,
                topic_3: logs[i].topics.length > 3 ? uint256(logs[i].topics[3]) : 0,
                data: logs[i].data,
                block_number: block.number,
                op_code: 0,
                block_hash: 0,
                tx_hash: uint256(keccak256(abi.encode(i, block.timestamp))),
                log_index: i
            });
            sys.dispatchLogToSubscribers(rec);
        }
        sys.executePendingCallbacks(proxy);
    }
}

contract SentinelOmniInvariantTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;

    SentinelInvariantHandler internal handler;
    SafeHavenReserve internal safeHaven;
    ProtectedCreditVault internal vault;
    DualProofDisputeMonitor internal monitor;

    function setUp() public {
        MockSystemContract impl = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        MockSystemContract sys = MockSystemContract(payable(SYSTEM_ADDR));
        MockCallbackProxy proxy = new MockCallbackProxy();

        safeHaven = new SafeHavenReserve();
        vault = new ProtectedCreditVault(true);
        MockDepegPool pool = new MockDepegPool();
        monitor = new DualProofDisputeMonitor();

        VaultSentinelCallback vCb = new VaultSentinelCallback(IPayable(payable(address(proxy))), address(0));
        VerifierSentinelCallback dCb = new VerifierSentinelCallback(IPayable(payable(address(proxy))), address(0));

        SentinelReactiveOmni sentinel = new SentinelReactiveOmni(
            84532,
            1301,
            84532,
            address(vault),
            address(pool),
            address(monitor),
            address(vCb),
            address(dCb),
            7_000,
            8_000
        );

        vCb.bindReactiveSender(address(sentinel));
        dCb.bindReactiveSender(address(sentinel));
        vault.setSafeHaven(safeHaven);
        vault.setSentinelCallback(address(vCb));
        monitor.setVerifierSentinelCallback(address(dCb));

        handler = new SentinelInvariantHandler(sys, proxy, vault, pool, monitor, sentinel);
        targetContract(address(handler));
    }

    function invariant_shareAccountingMatchesSumOfHolders() public view {
        uint256 sumShares = vault.sharesOf(handler.LP_A()) + vault.sharesOf(handler.LP_B());
        assertEq(vault.totalShares(), sumShares);
    }

    function invariant_safeHavenMatchesVaultAccounting() public view {
        assertEq(safeHaven.reservedBalanceOf(address(vault)), vault.safeReserveCash());
    }

    function invariant_equivocationAlwaysQuarantinesTee() public view {
        if (handler.equivocationOccurred()) {
            assertFalse(monitor.teeTrusted());
            assertEq(monitor.finalizationDelay(), 5 days);
            assertTrue(monitor.fastBridgePaused());
        }
    }
}
