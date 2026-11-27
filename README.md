# SentinelOmni — Autonomous Reactive DeFi Vault & Cross-Chain Verifier Immune System

> **Competition**: [DoraHacks — Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni) (Deadline: **2026-12-05 12:00 UTC**)
> **Primary Track**: **`Every Second Counts`** (Sub-Second Low-Latency DeFi across Unichain Sepolia + Reactive Lasna Omni + Base Sepolia)
> **Live Interactive Demo (Direct Base Sepolia RPC)**: https://ashunfeiyu.github.io/sentinel-omni/
> **Demo Video (2 min 18 sec)**: https://youtu.be/nJ8WcKpKQJ0
> **Live On-Chain Measured End-to-End Latency**: **`1.0 second`** (`VaultSentinelCallback.lastTotalLatencySec() == 1` across real public testnets!)

---

## 1. Why SentinelOmni? (Real Production Security DNA, Not a Toy)

Most hackathon automation entries implement simple token transfers or limit orders. **SentinelOmni** directly transforms two real-world high-severity smart contract vulnerabilities into an **autonomous, keeper-less, 1-second cross-chain immune system** built natively for **Reactive Omni** (`SYSTEM = 0x8888888888888888888888888888888888888888` and `SYSTEM.requestCallbackV_1_0`):

1. **Stale-NAV Vault Drain & Automated SafeHaven Liquidity Escape (`ProtectedCreditVault` + `SafeHavenReserve` + `VaultSentinelCallback`)**
   - **The Vulnerability**: When a credit/lending vault freezes intra-transaction NAV (`firstTotalAssets != 0`) and executes a discounted distressed sale (`forceSellable` / `recoveryBps < 100%`), an opportunistic attacker can redeem shares inside the same window at the stale `1.00` pre-loss NAV—extracting **100%** of newly recovered cash and leaving passive LPs with **0 USDC (100% wipeout)**.
   - **Reactive Omni 1-Second Defense**: `SentinelReactiveOmni` on **Reactive Lasna (`5318007`)** subscribes simultaneously to **Unichain Sepolia (`1301`)** collateral depeg shocks (`CollateralPriceShock`) and **Base Sepolia (`84532`)** vault distress events (`TxNavLocked`, `DistressedSaleExecuted`). When composite risk breaches `>= 7,000 bps` or a stale-NAV distressed sale occurs, `react()` calls `SYSTEM.requestCallbackV_1_0` to trigger `VaultSentinelCallback`: clearing stale `firstTotalAssets`, enforcing mathematically exact pro-rata settlement (`<= 1 wei` rounding error proven across 256 fuzz runs), migrating **80%** of cash (`40,000 USDC`) into external `SafeHavenReserve`, and recording on-chain end-to-end latency (`1s` live!).

2. **Dual-Proof (`TEE + ZK`) Verifier Equivocation Quarantine (`DualProofDisputeMonitor` + `VerifierSentinelCallback`)**
   - **The Vulnerability**: In multi-proof dispute games, once an honest ZK challenger calls `challenge()` on a fraudulent TEE proposal, permissionless `TEE_VERIFIER.nullify()` becomes permanently blocked—leaving the compromised TEE active with fast `1-day` finalization.
   - **Reactive Omni 1-Second Defense**: `SentinelReactiveOmni` captures `ConflictingRootObserved(gameId, rootA, rootB)`, proves equivocation (`rootA != rootB`) on-chain on Lasna, and dispatches `VerifierSentinelCallback.quarantineCompromisedVerifier(...)`, immediately setting `teeTrusted = false`, extending `finalizationDelay` from `1 days` to `5 days` (`432,000s`), and pausing fast bridge exits (`fastBridgePaused = true`).

3. **Zero-API Local AI Causal Risk Attribution Engine & Live RPC Dashboard (`ai_sentinel/` + `dashboard/`)**
   - Strictly **0 external/paid API calls**. Deterministic multi-chain causal analysis ingests real on-chain traces ([ai_sentinel/live_trace.json](ai_sentinel/live_trace.json)) to output structured root-cause classifications and latency benchmarks; [dashboard/index.html](dashboard/index.html) queries live Base Sepolia contract state directly via browser JSON-RPC `eth_call`.

---

## 2. Live Three-Chain Deployment & Verified Closed-Loop Proofs

Full record in [DEPLOYMENTS_LIVE.md](DEPLOYMENTS_LIVE.md).

### Deployed Contracts
| Network | Chain ID | Contract | Live Address |
| :--- | :--- | :--- | :--- |
| **Reactive Lasna** | `5318007` | `SentinelReactiveOmni` | [`0x6465c867144A08a9F8eCe82EB96c7179963015aB`](https://lasna.reactscan.net/address/0x6465c867144A08a9F8eCe82EB96c7179963015aB) |
| **Base Sepolia** | `84532` | `ProtectedCreditVault` | [`0x93bE0598B16eAbcf47DD987FEc433c9f34b2797C`](https://sepolia.basescan.org/address/0x93bE0598B16eAbcf47DD987FEc433c9f34b2797C) |
| **Base Sepolia** | `84532` | `SafeHavenReserve` | [`0x3De9748671B9BB9dd9171aad60f11C2A830cf29B`](https://sepolia.basescan.org/address/0x3De9748671B9BB9dd9171aad60f11C2A830cf29B) |
| **Base Sepolia** | `84532` | `VaultSentinelCallback` | [`0x42200AEAf0387903cCC0f5cB7D43798187a494C1`](https://sepolia.basescan.org/address/0x42200AEAf0387903cCC0f5cB7D43798187a494C1) |
| **Base Sepolia** | `84532` | `DualProofDisputeMonitor` | [`0x6644D4c0b2160e32684ec1ca81526090Bbc71A46`](https://sepolia.basescan.org/address/0x6644D4c0b2160e32684ec1ca81526090Bbc71A46) |
| **Base Sepolia** | `84532` | `VerifierSentinelCallback` | [`0x8359795be38719c55896Ca316201dEB0336479c8`](https://sepolia.basescan.org/address/0x8359795be38719c55896Ca316201dEB0336479c8) |
| **Unichain Sepolia** | `1301` | `MockDepegPool` | [`0x3De9748671B9BB9dd9171aad60f11C2A830cf29B`](https://sepolia.uniscan.xyz/address/0x3De9748671B9BB9dd9171aad60f11C2A830cf29B) |

### Verified Cross-Chain Closed Loops (`Origin -> Reactive react() -> Callback`)

**Loop A — Unichain Depeg + Base Stale-NAV Circuit Breaker & 80% SafeHaven Escape (`1.0s` E2E)**
1. **Unichain Origin (`1301`, Block `68931660`)**: `CollateralPriceShock (-45%)` → [`0xde012858...ecb4c`](https://sepolia.uniscan.xyz/tx/0xde012858f8f26504d0568656661841b7710f754f0388604a1e9297cb362ecb4c)
   - Reactive Lasna `react()` (Block `9377743`): [`0x7d3213d0...82d8`](https://lasna.reactscan.net/tx/0x7d3213d0197519f7a75b2d8197e4592d3a857cdbbdc775871bdd4d5a994982d8)
2. **Base Origin (`84532`, Block `64311140`, ts `1795784096`)**: `DistressedSaleExecuted (50% loss)` → [`0x9be45fae...e9c0`](https://sepolia.basescan.org/tx/0x9be45faee6798fc45cd2af16afd32025eb2b83faf7c0a2b6d69f5e635d74e9c0)
3. **Reactive Lasna (`5318007`, Block `9377751`)**: `SentinelReactiveOmni.react()` + `SYSTEM.requestCallbackV_1_0` → [`0xa945acd6...cfae`](https://lasna.reactscan.net/tx/0xa945acd6f28c1cffdcdec604872170449d40210c2766284ba6ee23bfac41cfae)
4. **Base Callback #1 (`84532`, Block `64311144`, ts `1795784097` = `+1s`)**: `triggerEmergencyCircuitBreaker` → [`0xaef5316c...f5ec`](https://sepolia.basescan.org/tx/0xaef5316cad57b15e8888537f4411dc3aa2cb92b27d3847b6febefbbbe291f5ec)
5. **Base Callback #2 (`84532`, Block `64311145`, ts `1795784097` = `+1s`)**: `executeSelfHealingRebalance` (`40,000 USDC` to SafeHaven) → [`0xd9c02190...e42da`](https://sepolia.basescan.org/tx/0xd9c02190f35f8fc3cdff75a9e1ec9eea486a54535bd96ef8797db2ba4b3e42da)

**Loop B — Dual-Proof TEE Equivocation Quarantine (`1.0s` E2E)**
1. **Base Origin (`84532`, Block `64311183`, ts `1795784105`)**: `ConflictingRootObserved (gameId = 621)` → [`0xfc8c0021...8e98`](https://sepolia.basescan.org/tx/0xfc8c0021c0378a00511b7cc8292cfe19903104adda5d0d35db47ca464b228e98)
2. **Reactive Lasna (`5318007`, Block `9377759`)**: `SentinelReactiveOmni.react()` + `SYSTEM.requestCallbackV_1_0` → [`0x4a4885d1...8e5`](https://lasna.reactscan.net/tx/0x4a4885d108cd776128983ecc9fbabfd6f3babf63560c971b3d3d3cc65eb138e5)
3. **Base Callback (`84532`, Block `64311187`, ts `1795784106` = `+1s`)**: `quarantineCompromisedVerifier` (`teeTrusted=false`, `finalizationDelay=5d`, `fastBridgePaused=true`) → [`0xb6527843...d90`](https://sepolia.basescan.org/tx/0xb6527843d7362537425f33e729784851ba02d10b354ebdff05282a94f5c67d90)

---

## 3. Architecture & Reactive Omni Compliance

```
[Unichain Sepolia (1301)]                 [Base Sepolia (84532)]
  MockDepegPool                             ProtectedCreditVault + SafeHavenReserve + DualProofDisputeMonitor
  └─ CollateralPriceShock                   └─ TxNavLocked / DistressedSaleExecuted / ConflictingRootObserved
           \                                       /
            \------> [Reactive Lasna (5318007)] <-/
                       SentinelReactiveOmni (AbstractReactive)
                       SYSTEM = 0x8888888888888888888888888888888888888888
                       └─ react(LogRecord) -> compositeRiskBps & rootA != rootB proof
                       └─ SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0)
                                    |
                                    v (1.0s measured E2E!)
                       [Base Sepolia Omni Callback Proxy]
                       (0x476F44b11F5C942c58f4c8E3d0300E5710743585)
                       Overwrites payload slot 0 with SentinelReactiveOmni address
                                    |
                    +---------------+---------------+
                    v                               v
         VaultSentinelCallback           VerifierSentinelCallback
       (onlyServiceProvider +          (onlyServiceProvider +
        onlyCallbackSender)             onlyCallbackSender)
```

---

## 4. Verification & Reproduction

```bash
# 1. Run unit, 256-run fuzz, and 64-run / 2,048-call stateful invariant tests (Solc 0.8.28)
forge test -vvv

# 2. Run zero-API local AI causal attribution on the live testnet trace
python3 ai_sentinel/analyzer.py --input ai_sentinel/live_trace.json

# 3. Open the interactive dashboard and click "Read Live Base Sepolia RPC State"
open dashboard/index.html
```

Verified test baseline:
- `SentinelOmniTest`: **7 / 7 PASS** (unit tests + 256-run fuzz proving pro-rata LP solvency `<= 1 wei`)
- `SentinelOmniInvariantTest`: **3 / 3 PASS** (`64 runs`, `2,048 calls`, `0 reverts`: share conservation, `SafeHavenReserve` accounting parity, and TEE equivocation quarantine guarantee)
