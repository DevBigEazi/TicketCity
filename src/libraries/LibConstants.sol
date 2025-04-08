// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title LibConstants
 * @dev Library to store constant values used across facets
 */
library LibConstants {
    // Initial stake amount for paid events (in smallest stablecoin units, e.g. 10 USDC)
    uint256 constant INITIAL_STAKE_AMOUNT = 10e6;
    uint256 constant FREE_TICKET_PRICE = 0;
    uint256 constant MINIMUM_ATTENDANCE_RATE = 60; // 60%
    uint256 constant FREE_EVENT_SERVICE_FEE_BASE = 25e5; // $2.5 in smallest units (assuming 6 decimals)
    uint256 constant FREE_EVENT_ATTENDEE_THRESHOLD = 50;
    uint256 constant PAID_EVENT_SERVICE_FEE_PERCENT = 5; // 5% of event total revenue
    // Flagging threshold for calculating fraud potential
    uint256 constant FLAGGING_THRESHOLD = 70; // This is used in a calculation where we check if flags exceed 70% of non-verified attendees
    uint256 constant SCAM_CONFIRM_PERIOD = 30 days;
    uint256 constant STAKE_PERCENTAGE = 20; // 20% of expected revenue must be staked
    uint256 constant FLAGGING_PERIOD = 4 days;
    uint256 constant PLATFORM_FEE_PERCENTAGE = 10;

    // Reputation system constants
    uint256 constant NEW_ORGANIZER_PENALTY = 10; // Additional stake percentage for new organizers
    uint256 constant REPUTATION_DISCOUNT_FACTOR = 5; // Stake percentage discount per successful event
    uint256 constant MAX_REPUTATION_DISCOUNT = 15; // Maximum stake discount percentage
}
