// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";

/**
 * @title EventManagementFacet
 * @dev Handles all event creation and management functionality
 */
contract EventManagementFacet {
    using Types for *;
    using Errors for *;

    /**
     * @dev Creates a new event with staking requirement
     * @param _title Event title
     * @param _desc Event description
     * @param _imageUri URI of the event image
     * @param _location Event location
     * @param _startDate Event start timestamp
     * @param _endDate Event end timestamp
     * @param _expectedAttendees Expected number of attendees
     * @param _ticketType Type of tickets for the event (FREE or PAID)
     * @return The ID of the newly created event
     */
    function createEvent(
        string memory _title,
        string memory _desc,
        string memory _imageUri,
        string memory _location,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _expectedAttendees,
        Types.TicketType _ticketType
    ) external payable returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        // Input validation
        if (msg.sender == address(0)) revert Errors.AddressZeroDetected();
        if (bytes(_title).length == 0 || bytes(_desc).length == 0)
            revert Errors.EmptyTitleOrDescription();
        if (_startDate >= _endDate || _startDate < block.timestamp)
            revert Errors.InvalidDates();
        if (_expectedAttendees == 0) revert Errors.ExpectedAttendeesIsTooLow();

        // Check if organizer is blacklisted
        require(!s.blacklistedOrganizers[msg.sender], "Organizer is blacklisted");

        // For PAID events, we'll collect a minimal initial stake
        uint256 initialStake = 0;
        if (_ticketType == Types.TicketType.PAID) {
            initialStake = 0.001 ether; // Minimal placeholder stake
            require(msg.value >= initialStake, "Insufficient initial stake");
        }

        uint256 eventId = s.totalEventOrganised + 1;
        s.totalEventOrganised = eventId;

        Types.EventDetails storage eventDetails = s.events[eventId];
        eventDetails.title = _title;
        eventDetails.desc = _desc;
        eventDetails.imageUri = _imageUri;
        eventDetails.location = _location;
        eventDetails.startDate = _startDate;
        eventDetails.endDate = _endDate;
        eventDetails.expectedAttendees = _expectedAttendees;
        eventDetails.ticketType = _ticketType;

        // Store initial stake amount
        s.stakedAmounts[eventId] = msg.value;

        // Initialize other values to zero
        eventDetails.userRegCount = 0;
        eventDetails.verifiedAttendeesCount = 0;
        eventDetails.ticketFee = 0;
        eventDetails.ticketNFTAddr = address(0);

        if (_ticketType == Types.TicketType.PAID) {
            eventDetails.paidTicketCategory = Types.PaidTicketCategory.NONE;
        } else {
            eventDetails.paidTicketCategory = Types.PaidTicketCategory.NONE;
        }

        eventDetails.organiser = msg.sender;
        s.allEvents.push(eventDetails);

        emit LibEvents.EventOrganized(msg.sender, eventId, _ticketType, msg.value);

        return eventId;
    }

    /**
     * @dev Calculate required stake based on organizer reputation and event details
     * @param _organiser The address of the event organizer
     * @param _expectedAttendees Expected number of attendees
     * @param _ticketType Type of event (FREE or PAID)
     * @param _estimatedTicketFee Estimated ticket fee (0 for FREE events)
     * @return Required stake amount
     */
    function calculateRequiredStake(
        address _organiser,
        uint256 _expectedAttendees,
        Types.TicketType _ticketType,
        uint256 _estimatedTicketFee
    ) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        // Free events have no stake requirement
        if (_ticketType == Types.TicketType.FREE) {
            return 0;
        }

        // For paid events, calculate stake based on expected revenue
        uint256 expectedRevenue = _expectedAttendees * _estimatedTicketFee;
        uint256 baseStakePercentage = LibConstants.STAKE_PERCENTAGE;

        // Apply penalties for new organizers or those with scam history
        if (s.organizerSuccessfulEvents[_organiser] == 0) {
            baseStakePercentage += LibConstants.NEW_ORGANIZER_PENALTY;
        }

        // Apply discounts for organizers with good reputation
        uint256 successEvents = s.organizerSuccessfulEvents[_organiser];
        uint256 reputationDiscount = 0;

        if (successEvents > 0) {
            reputationDiscount = successEvents * LibConstants.REPUTATION_DISCOUNT_FACTOR;
            if (reputationDiscount > LibConstants.MAX_REPUTATION_DISCOUNT) {
                reputationDiscount = LibConstants.MAX_REPUTATION_DISCOUNT;
            }
        }

        // Calculate final stake percentage (ensure it doesn't go below minimum)
        uint256 finalStakePercentage = 0;
        if (baseStakePercentage > reputationDiscount) {
            finalStakePercentage = baseStakePercentage - reputationDiscount;
        } else {
            finalStakePercentage = 5; // Minimum 5% stake even for best organizers
        }

        return (expectedRevenue * finalStakePercentage) / 100;
    }

    /**
     * @dev Retrieves details for a specific event
     * @param _eventId The ID of the event to retrieve
     * @return eventDetails The details of the event
     */
    function getEvent(
        uint256 _eventId
    ) public view returns (Types.EventDetails memory eventDetails) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        return eventDetails = s.events[_eventId];
    }

    /**
     * @dev Fetch all events created by a user that don't have tickets
     * @param _user Address of the event organizer
     * @return Array of event IDs without tickets
     */
    function getEventsWithoutTicketsByUser(
        address _user
    ) external view returns (uint256[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        if (_user == address(0)) revert Errors.AddressZeroDetected();

        // First get all events by the user
        uint256 eventCount = 0;

        // Count events organized by this user
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                eventCount++;
            }
        }

        // Create temporary array to hold all user's event IDs
        uint256[] memory allUserEvents = new uint256[](eventCount);
        uint256 userEventIndex = 0;

        // Fill array with user's event IDs
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                allUserEvents[userEventIndex] = i;
                userEventIndex++;
            }
        }

        // Count how many events don't have tickets
        uint256 noTicketCount = 0;
        for (uint256 i = 0; i < allUserEvents.length; i++) {
            uint256 eventId = allUserEvents[i];
            Types.EventDetails memory eventData = s.events[eventId];

            bool hasTickets = false;

            if (eventData.ticketType == Types.TicketType.FREE) {
                // For FREE events, check if ticketNFTAddr is not zero address
                hasTickets = eventData.ticketNFTAddr != address(0);
            } else if (eventData.ticketType == Types.TicketType.PAID) {
                // For PAID events, check if either regular or VIP tickets exist
                Types.TicketTypes memory tickets = s.eventTickets[eventId];
                hasTickets = tickets.hasRegularTicket || tickets.hasVIPTicket;
            }

            if (!hasTickets) {
                noTicketCount++;
            }
        }

        // Create array to hold events without tickets
        uint256[] memory eventsWithoutTickets = new uint256[](noTicketCount);

        // Fill the array with event IDs that don't have tickets
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < allUserEvents.length; i++) {
            uint256 eventId = allUserEvents[i];
            Types.EventDetails memory eventData = s.events[eventId];

            bool hasTickets = false;

            if (eventData.ticketType == Types.TicketType.FREE) {
                hasTickets = eventData.ticketNFTAddr != address(0);
            } else if (eventData.ticketType == Types.TicketType.PAID) {
                Types.TicketTypes memory tickets = s.eventTickets[eventId];
                hasTickets = tickets.hasRegularTicket || tickets.hasVIPTicket;
            }

            if (!hasTickets) {
                eventsWithoutTickets[resultIndex] = eventId;
                resultIndex++;
            }
        }

        return eventsWithoutTickets;
    }

    /**
     * @dev Returns all events organized by a specific user that have tickets
     * @param _user Address of the user whose organized events with tickets to fetch
     * @return Array of event IDs organized by the specified user that have tickets
     */
    function getEventsWithTicketByUser(
        address _user
    ) external view returns (uint256[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        if (_user == address(0)) revert Errors.AddressZeroDetected();

        uint256 count = 0;

        // First pass: count events organized by the specified user that have tickets
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                // Check if this event has tickets
                Types.EventDetails memory eventData = s.events[i];
                bool hasTickets = false;

                if (eventData.ticketType == Types.TicketType.FREE) {
                    // For FREE events, check if ticketNFTAddr is not zero address
                    hasTickets = eventData.ticketNFTAddr != address(0);
                } else if (eventData.ticketType == Types.TicketType.PAID) {
                    // For PAID events, check if either regular or VIP tickets exist
                    Types.TicketTypes memory tickets = s.eventTickets[i];
                    hasTickets = tickets.hasRegularTicket || tickets.hasVIPTicket;
                }

                if (hasTickets) {
                    count++;
                }
            }
        }

        // Create the array with the correct size
        uint256[] memory eventsWithTickets = new uint256[](count);
        uint256 index = 0;

        // Second pass: populate the array with events that have tickets
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                // Check if this event has tickets
                Types.EventDetails memory eventData = s.events[i];
                bool hasTickets = false;

                if (eventData.ticketType == Types.TicketType.FREE) {
                    // For FREE events, check if ticketNFTAddr is not zero address
                    hasTickets = eventData.ticketNFTAddr != address(0);
                } else if (eventData.ticketType == Types.TicketType.PAID) {
                    // For PAID events, check if either regular or VIP tickets exist
                    Types.TicketTypes memory tickets = s.eventTickets[i];
                    hasTickets = tickets.hasRegularTicket || tickets.hasVIPTicket;
                }

                if (hasTickets) {
                    eventsWithTickets[index] = i;
                    index++;
                }
            }
        }

        return eventsWithTickets;
    }

    /**
     * @dev Returns all valid events that have at least one ticket type created
     * @return Array of valid event IDs with available tickets
     */
    function getAllValidEvents() external view returns (uint256[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        uint256 count = 0;

        // First pass: count valid events
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            Types.EventDetails storage eventDetails = s.events[i];
            Types.TicketTypes storage tickets = s.eventTickets[i];

            bool hasTicket = false;

            // Check if event has tickets
            if (
                eventDetails.ticketType == Types.TicketType.FREE &&
                eventDetails.ticketNFTAddr != address(0)
            ) {
                hasTicket = true;
            } else if (tickets.hasRegularTicket || tickets.hasVIPTicket) {
                hasTicket = true;
            }

            if (hasTicket && eventDetails.endDate >= block.timestamp) {
                count++;
            }
        }

        // Second pass: populate the array
        uint256[] memory validEvents = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            Types.EventDetails storage eventDetails = s.events[i];
            Types.TicketTypes storage tickets = s.eventTickets[i];

            bool hasTicket = false;

            // Check if event has tickets
            if (
                eventDetails.ticketType == Types.TicketType.FREE &&
                eventDetails.ticketNFTAddr != address(0)
            ) {
                hasTicket = true;
            } else if (tickets.hasRegularTicket || tickets.hasVIPTicket) {
                hasTicket = true;
            }

            if (hasTicket && eventDetails.endDate >= block.timestamp) {
                validEvents[index] = i;
                index++;
            }
        }

        return validEvents;
    }

    function _validateEventAndOrganizer(uint256 _eventId) internal view {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        
        if (msg.sender == address(0)) revert Errors.AddressZeroDetected();
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (msg.sender != s.events[_eventId].organiser)
            revert Errors.OnlyOrganiserCanCreateTicket();
    }
}