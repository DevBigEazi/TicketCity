// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title LibConstants
 * @dev Library to store constant values used across facets
 */
library LibConstants {
    // Flagging system constants
    uint256 constant FREE_TICKET_PRICE = 0;
    uint256 constant MINIMUM_ATTENDANCE_RATE = 51; // 60%
    uint256 constant FLAGGING_THRESHOLD = 70; // 70% of ticket buyers need to flag
    uint256 constant SCAM_CONFIRM_PERIOD = 30 days; // 7 day waiting period after event ends
    uint256 constant STAKE_PERCENTAGE = 20; // 20% of expected revenue must be staked
    uint256 constant FLAGGING_PERIOD = 4 days;

    // Reputation system constants
    uint256 constant NEW_ORGANIZER_PENALTY = 10; // Additional stake percentage for new organizers
    uint256 constant REPUTATION_DISCOUNT_FACTOR = 5; // Stake percentage discount per successful event
    uint256 constant MAX_REPUTATION_DISCOUNT = 15; // Maximum stake discount percentage
}
