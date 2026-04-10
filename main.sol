// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Musha
 * "Capsules" are time-locked commitments that later reveal a secret to claim ETH.
 *
 * Notes:
 * - No hardcoded addresses.
 * - Owner is the deployer.
 * - Guardian defaults to the deployer and can be rotated.
 * - Direct ETH transfers are rejected; ETH enters only via createCapsule().
 */
contract Musha {
    // ----------- Custom errors -----------
    error Musha_ZeroCommitment();
    error Musha_AlreadyExists(bytes32 id);
    error Musha_NotCreator();
    error Musha_TooEarly(uint64 unlockTime);
    error Musha_AlreadyClaimed();
    error Musha_WrongSecret();
    error Musha_FeeTooLow(uint256 sent, uint256 required);
    error Musha_Paused();
    error Musha_NotAuthorized();
    error Musha_BadGuardian();
    error Musha_TransferFailed();

    // ----------- Events -----------
    event CapsuleForged(bytes32 indexed id, address indexed creator, uint64 unlockTime, uint256 stake, bytes32 commitment);
    event CapsuleCracked(bytes32 indexed id, address indexed claimer, bytes32 secretHash);
    event CapsuleScrapped(bytes32 indexed id, address indexed creator);
    event GuardianShifted(address indexed oldGuardian, address indexed newGuardian);
    event PauseToggled(bool paused);
    event FeesSwept(address indexed to, uint256 amount);

    // ----------- Capsule storage -----------
    struct Capsule {
        address creator;
        uint64 unlockTime;
        uint96 stake; // stake excluding fee
        bytes32 commitment; // keccak256(abi.encodePacked(secret, claimer))
        bool claimed;
    }

    // ----------- Access control -----------
    address public immutable owner;
    address public guardian;
    bool public paused;

    // ----------- Economics -----------
    uint256 public constant FORGE_FEE_WEI = 270_001_337_000_000; // 0.000270001337 ETH
    uint256 public constant MIN_STAKE_WEI = 3_000_000_000_000_000; // 0.003 ETH

    uint256 public feeBalance;
    mapping(bytes32 => Capsule) private _capsules;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Musha_NotAuthorized();
        _;
    }

    modifier onlyGuardianOrOwner() {
        if (msg.sender != owner && msg.sender != guardian) revert Musha_NotAuthorized();
        _;
