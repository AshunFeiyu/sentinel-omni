// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockDepegPool
 * @notice Models a fast L2 DEX / collateral pool on Unichain Sepolia (1301) emitting
 *         sub-second price shock telemetry with exact origin timestamps for latency measurement.
 */
contract MockDepegPool {
    uint256 public constant BPS = 10_000;
    uint256 public currentPriceE18 = 1e18;

    event CollateralPriceShock(
        address indexed targetVault,
        uint256 prevPriceE18,
        uint256 newPriceE18,
        uint256 shockBps,
        uint256 originTimestamp
    );

    function reportSwapPrice(address targetVault, uint256 newPriceE18) external {
        uint256 prev = currentPriceE18;
        uint256 shockBps = 0;
        if (newPriceE18 < prev && prev > 0) {
            shockBps = ((prev - newPriceE18) * BPS) / prev;
        }
        currentPriceE18 = newPriceE18;
        emit CollateralPriceShock(targetVault, prev, newPriceE18, shockBps, block.timestamp);
    }
}
