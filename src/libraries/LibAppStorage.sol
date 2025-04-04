// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./LibTypes.sol";

/**
 * @title LibAppStorage
 * @dev Storage layout for the Diamond pattern implementation of Ticket_City
 */
library LibAppStorage {
    struct AppStorage {
        // Core contract variables
        address payable owner;
        uint256 totalEventOrganised;
        uint256 totalTicketCreated;
        uint256 totalPurchasedTicket;
        // All events array
        LibTypes.EventDetails[] allEvents;
        // Mappings
        mapping(uint256 => LibTypes.EventDetails) events;
        mapping(address => mapping(uint256 => bool)) hasRegistered;
        mapping(address => mapping(uint256 => uint256)) organiserRevBal;
        mapping(uint256 => LibTypes.TicketTypes) eventTickets;
        mapping(address => mapping(uint256 => bool)) isVerified;
        mapping(uint256 => bool) revenueReleased;
        mapping(address => mapping(uint256 => bool)) hasFlaggerdEvent;
        mapping(uint256 => uint256) totalFlagsCount;
        mapping(uint256 => bool) flaggingPeriodEnded;
        mapping(uint256 => uint256) stakedAmounts;
        mapping(address => uint256) organizerSuccessfulEvents;
        mapping(address => uint256) organizerScammedEvents;
        mapping(address => mapping(uint256 => uint256)) flaggingWeight;
        mapping(uint256 => bool) eventDisputed;
        mapping(uint256 => string) disputeEvidence;
        mapping(address => mapping(uint256 => bytes)) attendanceProofs;
        mapping(uint256 => uint256) damageFeesPaid;
        mapping(address => bool) blacklistedOrganizers;
        // Merkle tree for attendance verification
        mapping(uint256 => bytes32) eventMerkleRoots;
        mapping(uint256 => address[]) eventAttendees;
        // Mappings for flagging system
        mapping(address => int256) userReputationScores;
        mapping(address => mapping(uint256 => LibTypes.FlagData)) flagData;
        mapping(uint256 => uint256) compensationPool;
        mapping(address => mapping(uint256 => uint256)) flaggingStakes;
        mapping(uint256 => address[]) eventFlaggers;
        mapping(uint256 => uint256) verificationTimes;
        mapping(address => mapping(uint256 => bool)) hasClaimed;
        // Dispute resolution system
        mapping(uint256 => LibTypes.DisputeResolution) disputeResolutions;
        mapping(bytes32 => uint256) pendingResolutions;
        // Supported tokens system
        mapping(address => bool) supportedTokens;
        address[] supportedTokensList;
    }
}
