// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title LibConstants
 * @dev Library to store constant values used across facets
 */
library LibConstants {
    // Flagging system constants
    uint256 constant FREE_TICKET_PRICE = 0;
    uint256 constant MINIMUM_ATTENDANCE_RATE = 60; // 60%
    uint256 constant FLAGGING_THRESHOLD = 80; // 80% of ticket buyers need to flag
    uint256 constant WAITING_PERIOD = 7 days; // 7 day waiting period after event ends
    uint256 constant STAKE_PERCENTAGE = 30; // 30% of expected revenue must be staked
    uint256 constant MAX_ALLOWED_SCAM_EVENTS = 1; // Maximum scam events before blacklisting

    uint256 constant MINIMUM_FLAG_STAKE = 0.01 ether; // Minimum stake required to flag an event
    uint256 constant DISPUTE_PERIOD = 3 days; // Period after flagging for organizer to dispute
    uint256 constant JURY_SIZE = 5; // Number of jurors for second-tier dispute resolution
    uint256 constant JURY_SELECTION_SEED = 42; // Seed for pseudo-random jury selection
    uint256 constant DISPUTE_RESOLUTION_THRESHOLD = 60; // 60% of jury must agree
    uint256 constant CLAIM_PERIOD = 30 days; // Period to claim refunds or compensation

    // Reputation system constants
    uint256 constant NEW_ORGANIZER_PENALTY = 10; // Additional stake percentage for new organizers
    uint256 constant REPUTATION_DISCOUNT_FACTOR = 5; // Stake percentage discount per successful event
    uint256 constant MAX_REPUTATION_DISCOUNT = 15; // Maximum stake discount percentage
    int256 constant MIN_REPUTATION_SCORE = -100; // Minimum reputation score
    int256 constant MAX_REPUTATION_SCORE = 100; // Maximum reputation score
    uint256 constant REPUTATION_CHANGE_BASE = 5; // Base reputation change amount
}
