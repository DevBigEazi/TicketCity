// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibTypes.sol";

/**
 * @title LibEvents
 * @dev Events used throughout the Ticket_City contract system
 */
library LibEvents {
    // Core events
    event EventOrganized(
        address indexed _organiser,
        address indexed _paymentToken,
        uint256 indexed _eventId,
        LibTypes.TicketType _ticketType,
        uint256 _stakedAmount
    );

    /**
     * @dev Emitted when a new ticket is created
     */
    event TicketCreated(
        uint256 indexed eventId,
        address indexed creator,
        address ticketNFTAddr,
        uint256 ticketFee,
        string ticketType
    );

    /**
     * @dev Emitted when a ticket is purchased
     */
    event TicketPurchased(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 price
    );

    /**
     * @dev Emitted when an attendee is verified
     */
    event AttendeeVerified(
        uint256 indexed eventId,
        address indexed attendee,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a Merkle root is set for an event
     */
    event MerkleRootSet(uint256 indexed eventId, bytes32 merkleRoot);

    event RevenueReleased(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount,
        uint256 _attendanceRate,
        bool _manuallyReleased
    );

    event EtherReceived(address indexed _from, uint _amount);

    event EventFlagged(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint256 _flagTime,
        uint256 _weight
    );

    event RefundProcessed(
        uint256 indexed _eventId,
        address indexed _buyer,
        uint256 _amount
    );

    event ReputationChanged(
        address indexed _user,
        int256 _newReputationScore,
        int256 _change
    );

    event EventDisputed(
        uint256 indexed _eventId,
        address indexed _organiser,
        string _evidence
    );

    event StakeRefunded(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount
    );

    event DamageFeeRefunded(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount
    );

    event OrganizerBlacklisted(address indexed _organiser, uint256 _timestamp);

    event OrganizerUnblacklisted(
        address indexed _organiser,
        uint256 _timestamp
    );

    // Flagging system events
    event DetailedEventFlagged(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint8 _reasonCode,
        string _evidence,
        uint256 _stake
    );

    event FalseFlaggerPenalized(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint256 _stake
    );

    event DisputeInitiated(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint8 _tier
    );

    event DisputeResolved(
        uint256 indexed _eventId,
        bool _inFavorOfOrganizer,
        uint8 _resolutionTier
    );

    event JurySelected(uint256 indexed _eventId, address[] _juryMembers);

    event JuryVoteSubmitted(
        uint256 indexed _eventId,
        address indexed _juror,
        bool _supportOrganizer
    );

    event CompensationClaimed(
        uint256 indexed _eventId,
        address indexed _claimer,
        uint256 _amount
    );
}
