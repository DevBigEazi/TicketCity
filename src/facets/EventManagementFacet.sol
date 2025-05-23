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
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title EventManagementFacet
 * @dev Handles all event creation and management functionality
 */
contract EventManagementFacet is ReentrancyGuard {
    LibAppStorage.AppStorage internal s;

    using LibTypes for *;
    using LibErrors for *;
    using SafeERC20 for IERC20;

    // createEventWithPermit args grouped to reduce stack variables
    struct EventCreateParams {
        string title;
        string desc;
        string imageUri;
        string location;
        uint256 startDate;
        uint256 endDate;
        uint256 expectedAttendees;
        LibTypes.TicketType ticketType;
        IERC20Permit paymentToken;
    }

    struct SignatureParams {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @dev Creates a new event with staking requirement using ERC20Permit for approval
     * @param _params Struct containing event parameters
     * @param _sig Struct containing signature parameters
     * @return The ID of the newly created event
     */
    function createEventWithPermit(
        EventCreateParams calldata _params,
        SignatureParams calldata _sig
    ) external nonReentrant returns (uint256) {
        // Input validation
        if (msg.sender == address(0)) revert LibErrors.AddressZeroDetected();
        if (
            bytes(_params.title).length == 0 || bytes(_params.desc).length == 0
        ) {
            revert LibErrors.EmptyTitleOrDescription();
        }
        // Check title, desc and location length
        if (
            bytes(_params.title).length > 32 ||
            bytes(_params.desc).length > 32 ||
            bytes(_params.location).length > 32
        ) {
            revert LibErrors.ReasonTooLong();
        }
        if (
            _params.startDate >= _params.endDate ||
            _params.startDate < block.timestamp
        ) {
            revert LibErrors.InvalidDates();
        }
        if (_params.expectedAttendees <= 5) {
            revert LibErrors.ExpectedAttendeesIsTooLow();
        }

        // Check if organizer is blacklisted
        if (s.blacklistedOrganizers[msg.sender] == true) {
            revert LibErrors.OrganizerIsBlacklisted();
        }

        // Check if the token is supported
        if (_params.ticketType == LibTypes.TicketType.PAID) {
            if (
                address(_params.paymentToken) != address(0) &&
                !s.supportedTokens[address(_params.paymentToken)]
            ) {
                revert LibErrors.TokenNotSupported();
            }
        }

        // For PAID events, we'll collect a minimal initial stake
        uint256 initialStake = 0;
        if (_params.ticketType == LibTypes.TicketType.PAID) {
            initialStake = _handlePaidEventStaking(_params.paymentToken, _sig);
        }

        uint256 eventId = s.totalEventOrganised + 1;
        s.totalEventOrganised = eventId;

        _createEventDetails(eventId, _params, initialStake);

        emit LibEvents.EventCreated(
            msg.sender,
            address(_params.paymentToken),
            eventId,
            _params.ticketType,
            initialStake
        );

        return eventId;
    }

    /**
     * @dev Handles staking for paid events
     * @param _paymentToken The token used for staking
     * @param _sig Signature parameters
     * @return initialStake The amount staked
     */
    function _handlePaidEventStaking(
        IERC20Permit _paymentToken,
        SignatureParams calldata _sig
    ) private returns (uint256) {
        uint256 initialStake = LibConstants.INITIAL_STAKE_AMOUNT;

        // Check if the payment token is valid
        if (
            IERC20(address(_paymentToken)).balanceOf(msg.sender) < initialStake
        ) {
            revert LibErrors.InsufficientInitialStake();
        }

        // deadline of 30 minutes from now to prevent stale signatures
        uint256 deadline = block.timestamp + 30 minutes;

        // Check deadline is valid (must be in the future)
        if (deadline < block.timestamp) {
            revert LibErrors.ExpiredDeadline();
        }

        // handle potential failures (front-running protection)
        try
            _paymentToken.permit(
                msg.sender,
                address(this),
                initialStake,
                deadline,
                _sig.v,
                _sig.r,
                _sig.s
            )
        {
            // Convert to IERC20 to use SafeERC20 functions
            IERC20 token = IERC20(address(_paymentToken));

            // Transfer the initial stake to the contract
            token.safeTransferFrom(msg.sender, address(this), initialStake);

            emit IExtendedERC20.Transfer(
                msg.sender,
                address(this),
                initialStake
            );
        } catch {
            // If permit fails, fall back to requiring approval via regular approve
            revert LibErrors.PermitFailed();
        }

        return initialStake;
    }

    /**
     * @dev Creates event details in storage
     * @param eventId The event ID
     * @param _params Event parameters
     * @param initialStake Initial stake amount
     */
    function _createEventDetails(
        uint256 eventId,
        EventCreateParams calldata _params,
        uint256 initialStake
    ) private {
        LibTypes.EventDetails storage eventDetails = s.events[eventId];
        eventDetails.title = _params.title;
        eventDetails.imageUri = _params.imageUri;
        eventDetails.location = _params.location;
        eventDetails.startDate = _params.startDate;
        eventDetails.endDate = _params.endDate;
        eventDetails.expectedAttendees = _params.expectedAttendees;
        eventDetails.ticketType = _params.ticketType;
        eventDetails.paymentToken = address(_params.paymentToken);

        // Store initial stake amount
        s.stakedAmounts[eventId] = initialStake;

        // Initialize other values to zero
        eventDetails.userRegCount = 0;
        eventDetails.verifiedAttendeesCount = 0;
        eventDetails.ticketFee = 0;
        eventDetails.ticketNFTAddr = address(0);

        if (_params.ticketType == LibTypes.TicketType.PAID) {
            eventDetails.paidTicketCategory = LibTypes.PaidTicketCategory.NONE;
        } else {
            eventDetails.paidTicketCategory = LibTypes.PaidTicketCategory.NONE;
        }

        eventDetails.organiser = msg.sender;
        s.allEvents.push(eventDetails);
    }

    /**
     * @dev Retrieves details for a specific event
     * @param _eventId The ID of the event to retrieve
     * @return eventDetails The details of the event
     */
    function getEvent(
        uint256 _eventId
    ) public view returns (LibTypes.EventDetails memory eventDetails) {
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
