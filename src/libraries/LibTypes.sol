// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title LibTypes
 * @dev Library for type definitions used across facets
 */
library LibTypes {
    enum TicketType {
        FREE,
        PAID
    }

    enum PaidTicketCategory {
        NONE,
        REGULAR,
        VIP
    }

    struct EventDetails {
        string title;
        string desc;
        string imageUri;
        string location;
        uint256 startDate;
        uint256 endDate;
        uint256 expectedAttendees;
        uint256 userRegCount;
        uint256 verifiedAttendeesCount;
        TicketType ticketType;
        PaidTicketCategory paidTicketCategory;
        address ticketNFTAddr;
        uint256 ticketFee;
        address organiser;
        address paymentToken;
    }

    struct TicketTypes {
        bool hasRegularTicket;
        bool hasVIPTicket;
        uint256 regularTicketFee;
        uint256 vipTicketFee;
        address regularTicketNFT;
        address vipTicketNFT;
    }

    struct FlagData {
        string evidence;
        uint256 timestamp;
    }
}
