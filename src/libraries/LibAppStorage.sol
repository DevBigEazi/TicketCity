// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./LibTypes.sol";

/**
 * @title LibAppStorage
 * @dev Storage layout for the Diamond pattern implementation of Ticket_City
 */
library LibAppStorage {
    struct AppStorage {
        // Mappings for events and tickets
        mapping(uint256 => LibTypes.EventDetails) events;
        mapping(address => mapping(uint256 => bool)) hasRegistered;
        mapping(address => mapping(uint256 => uint256)) organiserRevBal;
        mapping(uint256 => LibTypes.TicketTypes) eventTickets;
        mapping(address => mapping(uint256 => bool)) isVerified;
        mapping(uint256 => bool) revenueReleased;
        // Flagging system
        mapping(address => mapping(uint256 => bool)) hasFlaggedEvent;
        mapping(uint256 => uint256) totalFlagsCount;
        mapping(address => mapping(uint256 => uint256)) flaggingWeight;
        mapping(uint256 => bool) eventDisputed;
        mapping(uint256 => string) disputeEvidence;
        mapping(uint256 => uint256) manualReviewRequestTime;
        mapping(address => mapping(uint256 => LibTypes.FlagData)) flagData;
        // Scam event handling
        mapping(uint256 => bool) eventConfirmedScam;
        mapping(uint256 => string) scamConfirmationDetails;
        mapping(uint256 => uint256) scamConfirmationTime;
        mapping(address => mapping(uint256 => bool)) hasClaimedRefund;
        mapping(address => mapping(uint256 => uint256)) claimedRefundAmount;
        // Staking and financial
        mapping(uint256 => uint256) stakedAmounts;
        // Organizer reputation system
        mapping(address => uint256) organizerSuccessfulEvents;
        mapping(address => uint256) organizerScammedEvents;
        mapping(address => bool) blacklistedOrganizers;
        // Attendance verification
        mapping(uint256 => bytes32) eventVerificationCodes;
        mapping(uint256 => address[]) eventAttendees;
        // Supported tokens system
        mapping(address => bool) supportedTokens;
        address[] supportedTokensList;
        // Core contract variables
        address payable owner;
        uint256 totalEventOrganised;
        uint256 totalTicketCreated;
        uint256 totalPurchasedTicket;
        uint256 platformRevenue;
        uint256 organiserTotalRevenue;
        // All events array
        LibTypes.EventDetails[] allEvents;
    }
}
