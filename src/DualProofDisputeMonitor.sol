// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DualProofDisputeMonitor
 * @notice Models the Base-style Dual-Proof (`TEE + ZK`) dispute game equivocation bug where
 *         challenging a fraudulent TEE game blocks permissionless `TEE_VERIFIER.nullify()`,
 *         and demonstrates Reactive Omni cross-chain equivocation quarantine.
 */
contract DualProofDisputeMonitor {
    address public immutable owner;
    address public verifierSentinelCallback;

    uint256 public constant FAST_DELAY = 1 days;
    uint256 public constant SLOW_DELAY = 5 days;

    bool public teeTrusted = true;
    uint256 public finalizationDelay = FAST_DELAY;
    bool public fastBridgePaused;

    struct GameState {
        bytes32 proposedRoot;
        bool isTee;
        bool challenged;
        bool teeQuarantined;
    }

    mapping(uint256 => GameState) public games;

    event DisputeGameProposed(uint256 indexed gameId, bytes32 proposedRoot, bool isTee);
    event DisputeGameChallenged(
        uint256 indexed gameId,
        bytes32 proposedRoot,
        bytes32 canonicalRoot,
        bool teeStillTrusted
    );
    event ConflictingRootObserved(uint256 indexed gameId, bytes32 rootA, bytes32 rootB);
    event VerifierQuarantined(uint256 indexed gameId, bytes32 rootA, bytes32 rootB, uint256 newDelay);

    error OnlyOwner();
    error OnlySentinelCallback();
    error TeeNullifyBlockedAfterChallenge();
    error RootsDoNotConflict();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlySentinel() {
        if (msg.sender != verifierSentinelCallback) revert OnlySentinelCallback();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setVerifierSentinelCallback(address callback_) external onlyOwner {
        verifierSentinelCallback = callback_;
    }

    function proposeGame(uint256 gameId, bytes32 root, bool isTee) external {
        games[gameId] = GameState({
            proposedRoot: root,
            isTee: isTee,
            challenged: false,
            teeQuarantined: false
        });
        emit DisputeGameProposed(gameId, root, isTee);
    }

    /// @notice Models honest ZK challenger (or Sybil front-runner) challenging fraudulent TEE root.
    function challengeGame(uint256 gameId, bytes32 canonicalRoot) external {
        GameState storage g = games[gameId];
        if (canonicalRoot == g.proposedRoot) revert RootsDoNotConflict();
        g.challenged = true;
        emit DisputeGameChallenged(gameId, g.proposedRoot, canonicalRoot, teeTrusted);
        emit ConflictingRootObserved(gameId, g.proposedRoot, canonicalRoot);
    }

    /// @notice Reproduces the exact Base Everest `AggregateVerifier.nullify()` deadlock once challenged.
    function legacyNullifyTee(uint256 gameId, bytes32 conflictingRoot) external {
        GameState storage g = games[gameId];
        if (g.challenged) revert TeeNullifyBlockedAfterChallenge();
        if (conflictingRoot == g.proposedRoot) revert RootsDoNotConflict();
        teeTrusted = false;
        finalizationDelay = SLOW_DELAY;
    }

    /// @notice Autonomous cross-chain immune quarantine dispatched by SentinelReactiveOmni.
    function quarantineTeeFromReactive(
        uint256 gameId,
        bytes32 rootA,
        bytes32 rootB
    ) external onlySentinel {
        if (rootA == rootB) revert RootsDoNotConflict();
        games[gameId].teeQuarantined = true;
        teeTrusted = false;
        finalizationDelay = SLOW_DELAY;
        fastBridgePaused = true;
        emit VerifierQuarantined(gameId, rootA, rootB, SLOW_DELAY);
    }
}
