# SentinelOmni — Live Three-Chain Deployment & Verified Cross-Chain Closed-Loop Hashes

> **Competition**: DoraHacks — Reactive Omni Buildathon (`Every Second Counts`)
> **Verified On-Chain Date**: 2026-11-27
> **Measured On-Chain End-to-End Reaction Latency**: **`1 second`** (`VaultSentinelCallback.lastTotalLatencySec() == 1`)

---

## 1. Deployed Smart Contracts (Live Testnets)

| Network | Chain ID | Contract | Address |
| :--- | :--- | :--- | :--- |
| **Base Sepolia** | `84532` | `SafeHavenReserve` | `0x3De9748671B9BB9dd9171aad60f11C2A830cf29B` |
| **Base Sepolia** | `84532` | `ProtectedCreditVault` | `0x93bE0598B16eAbcf47DD987FEc433c9f34b2797C` |
| **Base Sepolia** | `84532` | `DualProofDisputeMonitor` | `0x6644D4c0b2160e32684ec1ca81526090Bbc71A46` |
| **Base Sepolia** | `84532` | `VaultSentinelCallback` | `0x42200AEAf0387903cCC0f5cB7D43798187a494C1` |
| **Base Sepolia** | `84532` | `VerifierSentinelCallback` | `0x8359795be38719c55896Ca316201dEB0336479c8` |
| **Unichain Sepolia** | `1301` | `MockDepegPool` | `0x3De9748671B9BB9dd9171aad60f11C2A830cf29B` |
| **Reactive Lasna** | `5318007` | `SentinelReactiveOmni` | `0x6465c867144A08a9F8eCe82EB96c7179963015aB` |

---

## 2. Verified Cross-Chain Closed-Loop Transactions (Origin → Reactive `react()` → Callback)

### Loop A: Multi-Chain Collateral Depeg + Stale-NAV Vault Circuit Breaker & 80% SafeHaven Escape
1. **Origin (Unichain Sepolia `1301`, Block `68931660`) — `CollateralPriceShock (-45%)`**:
   - Tx: `0xde012858f8f26504d0568656661841b7710f754f0388604a1e9297cb362ecb4c`
   - Explorer: https://sepolia.uniscan.xyz/tx/0xde012858f8f26504d0568656661841b7710f754f0388604a1e9297cb362ecb4c
   - **Reactive Lasna `react()` (Block `9377743`)**: `0x7d3213d0197519f7a75b2d8197e4592d3a857cdbbdc775871bdd4d5a994982d8`
   - ReactScan: https://lasna.reactscan.net/tx/0x7d3213d0197519f7a75b2d8197e4592d3a857cdbbdc775871bdd4d5a994982d8
2. **Origin (Base Sepolia `84532`, Block `64311121`) — `TxNavLocked`**:
   - Tx: `0x0f08232df44e323deedaaf0748682a36ca60046525920e1bdec21e4a3e3ebfc4`
   - **Reactive Lasna `react()` (Block `9377748`)**: `0x01e89dd0f224d4387331e310cd5840068d61c6ddfd9ef40984e6bf9aa0112254`
3. **Origin (Base Sepolia `84532`, Block `64311140`) — `DistressedSaleExecuted (50% haircut)`**:
   - Tx: `0x9be45faee6798fc45cd2af16afd32025eb2b83faf7c0a2b6d69f5e635d74e9c0`
   - BaseScan: https://sepolia.basescan.org/tx/0x9be45faee6798fc45cd2af16afd32025eb2b83faf7c0a2b6d69f5e635d74e9c0
4. **Reactive Lasna (`5318007`, Block `9377751`) — `SentinelReactiveOmni.react()` + `SYSTEM.requestCallbackV_1_0`**:
   - Tx: `0xa945acd6f28c1cffdcdec604872170449d40210c2766284ba6ee23bfac41cfae`
   - ReactScan: https://lasna.reactscan.net/tx/0xa945acd6f28c1cffdcdec604872170449d40210c2766284ba6ee23bfac41cfae
5. **Destination Callback #1 (Base Sepolia `84532`, Block `64311144`) — `VaultSentinelCallback.triggerEmergencyCircuitBreaker`**:
   - Tx: `0xaef5316cad57b15e8888537f4411dc3aa2cb92b27d3847b6febefbbbe291f5ec`
   - BaseScan: https://sepolia.basescan.org/tx/0xaef5316cad57b15e8888537f4411dc3aa2cb92b27d3847b6febefbbbe291f5ec
6. **Destination Callback #2 (Base Sepolia `84532`, Block `64311145`) — `VaultSentinelCallback.executeSelfHealingRebalance` (80% SafeHaven Migration)**:
   - Tx: `0xd9c02190f35f8fc3cdff75a9e1ec9eea486a54535bd96ef8797db2ba4b3e42da`
   - BaseScan: https://sepolia.basescan.org/tx/0xd9c02190f35f8fc3cdff75a9e1ec9eea486a54535bd96ef8797db2ba4b3e42da

### Loop B: Dual-Proof (`TEE + ZK`) Equivocation Quarantine
1. **Origin (Base Sepolia `84532`, Block `64311183`) — `ConflictingRootObserved` (`gameId = 621`)**:
   - Tx: `0xfc8c0021c0378a00511b7cc8292cfe19903104adda5d0d35db47ca464b228e98`
   - BaseScan: https://sepolia.basescan.org/tx/0xfc8c0021c0378a00511b7cc8292cfe19903104adda5d0d35db47ca464b228e98
2. **Reactive Lasna (`5318007`, Block `9377759`) — `SentinelReactiveOmni.react()` + `SYSTEM.requestCallbackV_1_0`**:
   - Tx: `0x4a4885d108cd776128983ecc9fbabfd6f3babf63560c971b3d3d3cc65eb138e5`
   - ReactScan: https://lasna.reactscan.net/tx/0x4a4885d108cd776128983ecc9fbabfd6f3babf63560c971b3d3d3cc65eb138e5
3. **Destination Callback (Base Sepolia `84532`, Block `64311187`) — `VerifierSentinelCallback.quarantineCompromisedVerifier`**:
   - Tx: `0xb6527843d7362537425f33e729784851ba02d10b354ebdff05282a94f5c67d90`
   - BaseScan: https://sepolia.basescan.org/tx/0xb6527843d7362537425f33e729784851ba02d10b354ebdff05282a94f5c67d90

---

## 3. Verified Live On-Chain State Post-Execution

- `ProtectedCreditVault.circuitBreakerActive()` = **`true`**
- `ProtectedCreditVault.firstTotalAssets()` = **`0`** (stale NAV cleared)
- `ProtectedCreditVault.safeReserveCash()` = **`40,000,000,000`** (`40,000 USDC`, 80% escaped to `SafeHavenReserve`)
- `ProtectedCreditVault.idleCash()` = **`10,000,000,000`** (`10,000 USDC`)
- `VaultSentinelCallback.interventionsExecuted()` = **`2`**
- `VaultSentinelCallback.lastTotalLatencySec()` = **`1`** (**1-second live end-to-end latency**)
- `DualProofDisputeMonitor.teeTrusted()` = **`false`**
- `DualProofDisputeMonitor.finalizationDelay()` = **`432000`** (`5 days`)
- `DualProofDisputeMonitor.fastBridgePaused()` = **`true`**
- `VerifierSentinelCallback.quarantinesExecuted()` = **`1`**
