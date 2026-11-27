// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IPayable} from "../src/reactive-omni/interfaces/IPayer.sol";
import {SafeHavenReserve} from "../src/SafeHavenReserve.sol";
import {ProtectedCreditVault} from "../src/ProtectedCreditVault.sol";
import {MockDepegPool} from "../src/MockDepegPool.sol";
import {DualProofDisputeMonitor} from "../src/DualProofDisputeMonitor.sol";
import {VaultSentinelCallback} from "../src/VaultSentinelCallback.sol";
import {VerifierSentinelCallback} from "../src/VerifierSentinelCallback.sol";
import {SentinelReactiveOmni} from "../src/SentinelReactiveOmni.sol";

/**
 * @title DeployDestinationBaseSepolia
 * @notice Step 1: Deploy SafeHavenReserve, ProtectedCreditVault, DualProofDisputeMonitor,
 *         and Callback receivers on Base Sepolia (84532).
 */
contract DeployDestinationBaseSepolia is Script {
    address public constant BASE_SEPOLIA_OMNI_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external {
        vm.startBroadcast();
        SafeHavenReserve safeHaven = new SafeHavenReserve();
        ProtectedCreditVault vault = new ProtectedCreditVault(true);
        DualProofDisputeMonitor monitor = new DualProofDisputeMonitor();

        VaultSentinelCallback vaultCb =
            new VaultSentinelCallback{value: 0.001 ether}(IPayable(payable(BASE_SEPOLIA_OMNI_PROXY)), address(0));
        VerifierSentinelCallback verifierCb =
            new VerifierSentinelCallback{value: 0.001 ether}(IPayable(payable(BASE_SEPOLIA_OMNI_PROXY)), address(0));

        vault.setSafeHaven(safeHaven);
        vault.setSentinelCallback(address(vaultCb));
        monitor.setVerifierSentinelCallback(address(verifierCb));
        vm.stopBroadcast();
    }
}

/**
 * @title DeployOriginUnichainSepolia
 * @notice Step 2: Deploy fast collateral price monitor pool on Unichain Sepolia (1301).
 */
contract DeployOriginUnichainSepolia is Script {
    function run() external {
        vm.startBroadcast();
        new MockDepegPool();
        vm.stopBroadcast();
    }
}

/**
 * @title DeployReactiveLasna
 * @notice Step 3: Deploy SentinelReactiveOmni on Reactive Lasna (5318007) subscribed to Base + Unichain.
 */
contract DeployReactiveLasna is Script {
    function run(
        address vault_,
        address pool_,
        address disputeMonitor_,
        address vaultCallback_,
        address verifierCallback_
    ) external {
        vm.startBroadcast();
        new SentinelReactiveOmni{value: 0.1 ether}(
            84532,
            1301,
            84532,
            vault_,
            pool_,
            disputeMonitor_,
            vaultCallback_,
            verifierCallback_,
            7_000,
            8_000
        );
        vm.stopBroadcast();
    }
}
