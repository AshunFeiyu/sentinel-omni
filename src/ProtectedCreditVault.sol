// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeHavenReserve} from "./SafeHavenReserve.sol";

/**
 * @title ProtectedCreditVault
 * @notice ERC-4626-style credit vault modeling real stale-NAV single-accrual drain
 *         (`firstTotalAssets` locked before distressed `forceSellable` loss realization) and
 *         proving sub-second autonomous protection + automated SafeHaven liquidity escape
 *         via Reactive Omni callbacks.
 */
contract ProtectedCreditVault {
    uint256 public constant BPS = 10_000;
    uint256 public constant WAD = 1e18;

    address public immutable owner;
    address public sentinelCallback;
    SafeHavenReserve public safeHaven;

    uint256 public totalShares;
    uint256 public idleCash;
    uint256 public creditBookValue;
    uint256 public safeReserveCash;

    /// @notice Models intra-transaction frozen NAV (`VaultV2.firstTotalAssets`)
    uint256 public firstTotalAssets;
    bool public sentinelEnabled;
    bool public circuitBreakerActive;
    uint256 public lastRealizedLossBps;

    mapping(address => uint256) public sharesOf;
    mapping(address => uint256) public cashOf;

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event TxNavLocked(
        address indexed vault,
        uint256 frozenTotalAssets,
        uint256 totalShares,
        uint256 originTimestamp
    );
    event DistressedSaleExecuted(
        address indexed vault,
        uint256 soldCredit,
        uint256 cashRecovered,
        uint256 lossBps,
        bool staleNavLocked,
        uint256 originTimestamp
    );
    event Redeemed(address indexed user, uint256 shares, uint256 assetsOut, bool proRataMode);
    event CircuitBreakerEngaged(
        uint256 reasonCode,
        uint256 realizedLossBps,
        uint256 trueAssetsAfterSync,
        uint256 reactionLatencySec
    );
    event LiquidityEscapedToSafeHaven(
        address indexed safeHaven,
        uint256 migratedAmount,
        uint256 remainingIdleCash,
        uint256 reactionLatencySec
    );

    error OnlyOwner();
    error OnlySentinelCallback();
    error ZeroAmount();
    error InsufficientShares();
    error InsufficientIdleLiquidity();
    error StaleNavRedemptionBlocked();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlySentinel() {
        if (msg.sender != sentinelCallback) revert OnlySentinelCallback();
        _;
    }

    constructor(bool sentinelEnabled_) {
        owner = msg.sender;
        sentinelEnabled = sentinelEnabled_;
    }

    function setSentinelCallback(address callback_) external onlyOwner {
        sentinelCallback = callback_;
    }

    function setSafeHaven(SafeHavenReserve safeHaven_) external onlyOwner {
        safeHaven = safeHaven_;
    }

    function setSentinelEnabled(bool enabled_) external onlyOwner {
        sentinelEnabled = enabled_;
    }

    function trueTotalAssets() public view returns (uint256) {
        return idleCash + safeReserveCash + creditBookValue;
    }

    function depositAllocated(address user, uint256 assets) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        uint256 supply = totalShares;
        uint256 nav = trueTotalAssets();
        shares = (supply == 0 || nav == 0) ? assets : (assets * supply) / nav;
        totalShares = supply + shares;
        sharesOf[user] += shares;
        creditBookValue += assets;
        emit Deposited(user, assets, shares);
    }

    function beginTxNavLock() external {
        if (firstTotalAssets == 0) {
            firstTotalAssets = trueTotalAssets();
            emit TxNavLocked(address(this), firstTotalAssets, totalShares, block.timestamp);
        }
    }

    function endTxNavLock() external {
        firstTotalAssets = 0;
    }

    function executeDistressedSale(uint256 recoveryBps) external {
        if (creditBookValue == 0 || recoveryBps > BPS) revert ZeroAmount();
        uint256 sold = creditBookValue;
        uint256 recovered = (sold * recoveryBps) / BPS;
        uint256 lossBps = BPS - recoveryBps;

        creditBookValue = 0;
        idleCash += recovered;
        lastRealizedLossBps = lossBps;

        emit DistressedSaleExecuted(
            address(this),
            sold,
            recovered,
            lossBps,
            firstTotalAssets != 0,
            block.timestamp
        );
    }

    function engageCircuitBreakerAndSync(
        uint256 reasonCode,
        uint256 lossBps,
        uint256 originTimestamp
    ) external onlySentinel {
        circuitBreakerActive = true;
        firstTotalAssets = 0;
        if (lossBps > lastRealizedLossBps) {
            lastRealizedLossBps = lossBps;
        }
        uint256 latency = block.timestamp >= originTimestamp ? block.timestamp - originTimestamp : 0;
        emit CircuitBreakerEngaged(reasonCode, lastRealizedLossBps, trueTotalAssets(), latency);
    }

    function isolateSafeReserve(uint256 targetReserveBps, uint256 originTimestamp) external onlySentinel {
        if (targetReserveBps > BPS) revert ZeroAmount();
        uint256 totalCash = idleCash + safeReserveCash;
        uint256 targetSafe = (totalCash * targetReserveBps) / BPS;
        uint256 moved = 0;
        if (targetSafe > safeReserveCash && idleCash > 0) {
            uint256 delta = targetSafe - safeReserveCash;
            moved = delta > idleCash ? idleCash : delta;
            idleCash -= moved;
            safeReserveCash += moved;
            if (address(safeHaven) != address(0)) {
                safeHaven.depositFromVault(moved);
            }
        }
        uint256 latency = block.timestamp >= originTimestamp ? block.timestamp - originTimestamp : 0;
        emit LiquidityEscapedToSafeHaven(address(safeHaven), moved, idleCash, latency);
    }

    function releaseCircuitBreaker() external onlyOwner {
        circuitBreakerActive = false;
    }

    function redeem(address user, uint256 shares) external returns (uint256 assetsOut) {
        if (shares == 0) revert ZeroAmount();
        if (sharesOf[user] < shares) revert InsufficientShares();

        if (sentinelEnabled && firstTotalAssets > 0 && lastRealizedLossBps > 0) {
            revert StaleNavRedemptionBlocked();
        }

        bool useStaleNav = (!sentinelEnabled && firstTotalAssets > 0);
        uint256 valuationBase = useStaleNav ? firstTotalAssets : trueTotalAssets();
        assetsOut = (shares * valuationBase) / totalShares;

        uint256 availableCash = idleCash + safeReserveCash;
        if (assetsOut > availableCash) revert InsufficientIdleLiquidity();

        sharesOf[user] -= shares;
        totalShares -= shares;

        if (assetsOut <= idleCash) {
            idleCash -= assetsOut;
        } else {
            uint256 rem = assetsOut - idleCash;
            idleCash = 0;
            safeReserveCash -= rem;
            if (address(safeHaven) != address(0)) {
                safeHaven.withdrawToVault(rem);
            }
        }
        cashOf[user] += assetsOut;

        emit Redeemed(user, shares, assetsOut, !useStaleNav);
    }
}
