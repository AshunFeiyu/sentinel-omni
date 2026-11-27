// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SafeHavenReserve
 * @notice Minimal segregated safe-haven liquidity reserve on Base Sepolia (84532)
 *         receiving automated sub-second emergency liquidity migrations from
 *         ProtectedCreditVault during cross-chain collateral depeg or distressed sales.
 */
contract SafeHavenReserve {
    mapping(address => uint256) public reservedBalanceOf;
    uint256 public totalReserved;

    event SafeHavenDeposited(address indexed vault, uint256 amount, uint256 newVaultReserve);
    event SafeHavenWithdrawn(address indexed vault, uint256 amount, uint256 remainingVaultReserve);

    error InsufficientReserve();

    function depositFromVault(uint256 amount) external {
        reservedBalanceOf[msg.sender] += amount;
        totalReserved += amount;
        emit SafeHavenDeposited(msg.sender, amount, reservedBalanceOf[msg.sender]);
    }

    function withdrawToVault(uint256 amount) external {
        if (reservedBalanceOf[msg.sender] < amount) revert InsufficientReserve();
        reservedBalanceOf[msg.sender] -= amount;
        totalReserved -= amount;
        emit SafeHavenWithdrawn(msg.sender, amount, reservedBalanceOf[msg.sender]);
    }
}
