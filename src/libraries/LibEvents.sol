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

    /**
     * @dev Emitted when event revenue is released to organizer
     */
    event RevenueReleased(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount,
        uint256 _attendanceRate,
        bool _manuallyReleased
    );

    /**
     * @dev Emitted when Ether is received by the contract
     */
    event EtherReceived(address indexed _from, uint256 _amount);

    /**
     * @dev Emitted when event is flagged by an attendee
     */
    event EventFlagged(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint256 _flagTime,
        uint256 _weight
    );

    /**
     * @dev Emitted when a refund is processed for a ticket buyer
     */
    event RefundProcessed(
        uint256 indexed _eventId,
        address indexed _buyer,
        uint256 _amount
    );

    /**
     * @dev Emitted when reputation score changes
     */
    event ReputationChanged(
        address indexed _user,
        int256 _newReputationScore,
        int256 _change
    );

    /**
     * @dev Emitted when an event is disputed by the organizer
     */
    event EventDisputed(
        uint256 indexed _eventId,
        address indexed _organiser,
        string _evidence
    );

    /**
     * @dev Emitted when stake is refunded to an organizer
     */
    event StakeRefunded(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount
    );

    /**
     * @dev Emitted when damage fee is refunded to the organizer
     */
    event DamageFeeRefunded(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint256 _amount
    );

    /**
     * @dev Emitted when an organizer is blacklisted
     */
    event OrganizerBlacklisted(address indexed _organiser, uint256 _timestamp);

    /**
     * @dev Emitted when an organizer is unblacklisted
     */
    event OrganizerUnblacklisted(
        address indexed _organiser,
        uint256 _timestamp
    );

    /**
     * @dev Emitted when an event is flagged with detailed information
     */
    event DetailedEventFlagged(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint8 _reasonCode,
        string _evidence,
        uint256 _stake
    );

    /**
     * @dev Emitted when a false flagger is penalized
     */
    event FalseFlaggerPenalized(
        uint256 indexed _eventId,
        address indexed _flagger,
        uint256 _stake
    );

    /**
     * @dev Emitted when a dispute is initiated
     */
    event DisputeInitiated(
        uint256 indexed _eventId,
        address indexed _organiser,
        uint8 _tier
    );

    /**
     * @dev Emitted when a dispute is resolved
     */
    event DisputeResolved(
        uint256 indexed _eventId,
        bool _inFavorOfOrganizer,
        uint8 _resolutionTier
    );

    /**
     * @dev Emitted when jury members are selected for dispute resolution
     */
    event JurySelected(uint256 indexed _eventId, address[] _juryMembers);

    /**
     * @dev Emitted when a juror submits a vote in dispute resolution
     */
    event JuryVoteSubmitted(
        uint256 indexed _eventId,
        address indexed _juror,
        bool _supportOrganizer
    );

    /**
     * @dev Emitted when compensation is claimed
     */
    event CompensationClaimed(
        uint256 indexed _eventId,
        address indexed _claimer,
        uint256 _amount
    );

    // New events for scam event handling

    /**
     * @dev Emitted when an event is confirmed as a scam by the contract owner
     */
    event EventConfirmedAsScam(
        uint256 indexed _eventId,
        uint256 _confirmationTime,
        string _details
    );

    /**
     * @dev Emitted when a refund is claimed for a scam event
     */
    event RefundClaimed(
        uint256 indexed _eventId,
        address indexed _attendee,
        uint256 _totalAmount,
        uint256 _stakeShare
    );

    /**
     * @dev Emitted when platform revenue is collected from scam events
     */
    event PlatformRevenueCollected(uint256 indexed _eventId, uint256 _amount);

    /**
     * @dev Emitted when manual review is requested by organizer
     */
    event ManualReviewRequested(
        uint256 indexed _eventId,
        address indexed _organiser,
        string _explanation
    );
}
