// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title Types
 * @dev Data structures used throughout the Ticket_City contract system
 */
library Types {
    enum TicketType {
        FREE,
        PAID
    }

    enum PaidTicketCategory {
        NONE,
        REGULAR,
        VIP
    }

    enum FlagReason {
        NoShow,
        FalseAdvertising,
        SafetyConcerns,
        InappropriateContent,
        Other
    }

    // Structure for flag data with evidence
    struct FlagData {
        FlagReason reason;
        string evidence;
        uint256 timestamp;
        uint256 stake;
    }

    // Structure for dispute resolution data
    struct DisputeResolution {
        bool inProgress;
        bool resolved;
        uint8 currentTier; // 1 = Algorithm-based, 2 = Jury-based, 3 = DAO governance
        address[] juryMembers;
        mapping(address => bool) juryVotes;
        uint256 positiveVotes;
        uint256 negativeVotes;
        string organizerEvidence;
        uint256 resolutionTimestamp;
    }

    struct EventDetails {
        string title;
        string desc;
        string imageUri;
        string location;
        uint256 startDate;
        uint256 endDate;
        uint256 expectedAttendees;
        TicketType ticketType;
        PaidTicketCategory paidTicketCategory;
        uint32 userRegCount;
        uint32 verifiedAttendeesCount;
        uint256 ticketFee;
        address ticketNFTAddr;
        address organiser;
    }

    struct TicketTypes {
        bool hasRegularTicket;
        bool hasVIPTicket;
        uint256 regularTicketFee;
        uint256 vipTicketFee;
        address regularTicketNFT;
        address vipTicketNFT;
    }
}
