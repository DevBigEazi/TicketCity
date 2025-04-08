// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibTypes.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibUtils.sol";
import "../interfaces/IExtendedERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EventManagementFacet
 * @dev Handles all event creation and management functionality
 */
contract EventManagementFacet is ReentrancyGuard {
    using LibTypes for *;
    using LibErrors for *;
    using SafeERC20 for IERC20;

    /**
     * @dev Creates a new event with staking requirement
     * @param _title Event title
     * @param _desc Event title
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
        LibTypes.TicketType _ticketType,
        IERC20 _paymentToken
    ) external nonReentrant returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Input validation
        if (msg.sender == address(0)) revert LibErrors.AddressZeroDetected();
        if (bytes(_title).length == 0 || bytes(_desc).length == 0) {
            revert LibErrors.EmptyTitleOrDescription();
        }
        if (_startDate >= _endDate || _startDate < block.timestamp) {
            revert LibErrors.InvalidDates();
        }
        if (_expectedAttendees <= 5) {
            revert LibErrors.ExpectedAttendeesIsTooLow();
        }

        // Check if organizer is blacklisted
        if (s.blacklistedOrganizers[msg.sender] == true) {
            revert LibErrors.OrganizerIsBlacklisted();
        }

        // Check if the token is supported
        if (_ticketType == LibTypes.TicketType.PAID) {
            if (
                address(_paymentToken) != address(0) &&
                !s.supportedTokens[address(_paymentToken)]
            ) {
                revert LibErrors.TokenNotSupported();
            }
        }

        // For PAID events, we'll collect a minimal initial stake
        uint256 initialStake = 0;
        if (_ticketType == LibTypes.TicketType.PAID) {
            initialStake = LibConstants.INITIAL_STAKE_AMOUNT;
            // Check if the payment token is valid
            if (_paymentToken.balanceOf(msg.sender) < initialStake) {
                revert LibErrors.InsufficientInitialStake();
            }
            if (
                _paymentToken.allowance(msg.sender, address(this)) <
                initialStake
            ) {
                revert LibErrors.InsufficientAllowance();
            }

            // Transfer the initial stake to the contract
            _paymentToken.safeTransferFrom(
                msg.sender,
                address(this),
                initialStake
            );

            emit IExtendedERC20.Transfer(
                msg.sender,
                address(this),
                initialStake
            );
        }

        uint256 eventId = s.totalEventOrganised + 1;
        s.totalEventOrganised = eventId;

        LibTypes.EventDetails storage eventDetails = s.events[eventId];
        eventDetails.title = _title;
        eventDetails.imageUri = _imageUri;
        eventDetails.location = _location;
        eventDetails.startDate = _startDate;
        eventDetails.endDate = _endDate;
        eventDetails.expectedAttendees = _expectedAttendees;
        eventDetails.ticketType = _ticketType;
        eventDetails.paymentToken = address(_paymentToken);

        // Store initial stake amount
        s.stakedAmounts[eventId] = initialStake;

        // Initialize other values to zero
        eventDetails.userRegCount = 0;
        eventDetails.verifiedAttendeesCount = 0;
        eventDetails.ticketFee = 0;
        eventDetails.ticketNFTAddr = address(0);

        if (_ticketType == LibTypes.TicketType.PAID) {
            eventDetails.paidTicketCategory = LibTypes.PaidTicketCategory.NONE;
        } else {
            eventDetails.paidTicketCategory = LibTypes.PaidTicketCategory.NONE;
        }

        eventDetails.organiser = msg.sender;
        s.allEvents.push(eventDetails);

        emit LibEvents.EventCreated(
            msg.sender,
            address(_paymentToken),
            eventId,
            _ticketType,
            initialStake
        );

        return eventId;
    }

    /**
     * @dev Retrieves details for a specific event
     * @param _eventId The ID of the event to retrieve
     * @return eventDetails The details of the event
     */
    function getEvent(
        uint256 _eventId
    ) public view returns (LibTypes.EventDetails memory eventDetails) {
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

        if (_user == address(0)) revert LibErrors.AddressZeroDetected();

        // First get all events by the user
        uint256 eventCount = 0;

        // Count events organized by this user
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                eventCount++;
            }
        }

        // temporary array to hold all user's event IDs
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
            LibTypes.EventDetails memory eventData = s.events[eventId];

            bool hasTickets = false;

            if (eventData.ticketType == LibTypes.TicketType.FREE) {
                // For FREE events, check if ticketNFTAddr is not zero address
                hasTickets = eventData.ticketNFTAddr != address(0);
            } else if (eventData.ticketType == LibTypes.TicketType.PAID) {
                // For PAID events, check if either regular or VIP tickets exist
                LibTypes.TicketTypes memory tickets = s.eventTickets[eventId];
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
            LibTypes.EventDetails memory eventData = s.events[eventId];

            bool hasTickets = false;

            if (eventData.ticketType == LibTypes.TicketType.FREE) {
                hasTickets = eventData.ticketNFTAddr != address(0);
            } else if (eventData.ticketType == LibTypes.TicketType.PAID) {
                LibTypes.TicketTypes memory tickets = s.eventTickets[eventId];
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

        if (_user == address(0)) revert LibErrors.AddressZeroDetected();

        uint256 count = 0;

        // First pass: count events organized by the specified user that have tickets
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.events[i].organiser == _user) {
                // Check if this event has tickets
                LibTypes.EventDetails memory eventData = s.events[i];
                bool hasTickets = false;

                if (eventData.ticketType == LibTypes.TicketType.FREE) {
                    // For FREE events, check if ticketNFTAddr is not zero address
                    hasTickets = eventData.ticketNFTAddr != address(0);
                } else if (eventData.ticketType == LibTypes.TicketType.PAID) {
                    // For PAID events, check if either regular or VIP tickets exist
                    LibTypes.TicketTypes memory tickets = s.eventTickets[i];
                    hasTickets =
                        tickets.hasRegularTicket ||
                        tickets.hasVIPTicket;
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
                LibTypes.EventDetails memory eventData = s.events[i];
                bool hasTickets = false;

                if (eventData.ticketType == LibTypes.TicketType.FREE) {
                    // For FREE events, check if ticketNFTAddr is not zero address
                    hasTickets = eventData.ticketNFTAddr != address(0);
                } else if (eventData.ticketType == LibTypes.TicketType.PAID) {
                    // For PAID events, check if either regular or VIP tickets exist
                    LibTypes.TicketTypes memory tickets = s.eventTickets[i];
                    hasTickets =
                        tickets.hasRegularTicket ||
                        tickets.hasVIPTicket;
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
            LibTypes.EventDetails storage eventDetails = s.events[i];
            LibTypes.TicketTypes storage tickets = s.eventTickets[i];

            bool hasTicket = false;

            // Check if event has tickets
            if (
                eventDetails.ticketType == LibTypes.TicketType.FREE &&
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
            LibTypes.EventDetails storage eventDetails = s.events[i];
            LibTypes.TicketTypes storage tickets = s.eventTickets[i];

            bool hasTicket = false;

            // Check if event has tickets
            if (
                eventDetails.ticketType == LibTypes.TicketType.FREE &&
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
}
