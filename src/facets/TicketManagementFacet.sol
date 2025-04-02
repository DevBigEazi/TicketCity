// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ITicket_NFT.sol";
import "../../src/Ticket_NFT.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TicketManagementFacet
 * @dev Handles ticket creation, purchase, and verification functionality
 */
contract TicketManagementFacet is ReentrancyGuard {
    using Types for *;
    using Errors for *;

    /**
     * @dev Creates a ticket for an existing event
     * @param _eventId The ID of the event
     * @param _category The category of the ticket (NONE for FREE, REGULAR or VIP for PAID events)
     * @param _ticketFee The price of the ticket (0 for FREE tickets)
     * @param _ticketUri The URI for the ticket metadata
     */
    function createTicket(
        uint256 _eventId,
        Types.PaidTicketCategory _category,
        uint256 _ticketFee,
        string memory _ticketUri
    ) external payable {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        _validateEventAndOrganizer(_eventId);

        Types.EventDetails storage eventDetails = s.events[_eventId];
        Types.TicketTypes storage tickets = s.eventTickets[_eventId];

        // Handle FREE tickets
        if (_category == Types.PaidTicketCategory.NONE) {
            if (eventDetails.ticketType != Types.TicketType.FREE) {
                revert Errors.FreeTicketForFreeEventOnly();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                LibConstants.FREE_TICKET_PRICE,
                _ticketUri,
                "FREE"
            );

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                LibConstants.FREE_TICKET_PRICE,
                "FREE"
            );
            return;
        }

        // Handle PAID tickets
        if (eventDetails.ticketType != Types.TicketType.PAID) {
            revert Errors.YouCanNotCreateThisTypeOfTicketForThisEvent();
        }
        if (_ticketFee == 0) revert Errors.InvalidTicketFee();

        // If this is the first ticket being created, calculate and collect proper stake
        bool firstTicket = !tickets.hasRegularTicket && !tickets.hasVIPTicket;

        if (firstTicket) {
            // Calculate required stake based on this ticket's price
            uint256 requiredStake = calculateRequiredStake(
                msg.sender,
                eventDetails.expectedAttendees,
                Types.TicketType.PAID,
                _ticketFee
            );

            // Subtract any stake already provided
            uint256 existingStake = s.stakedAmounts[_eventId];
            uint256 additionalStakeNeeded = 0;

            if (requiredStake > existingStake) {
                additionalStakeNeeded = requiredStake - existingStake;
            }

            // Require additional stake if needed
            require(
                msg.value >= additionalStakeNeeded,
                "Insufficient stake amount"
            );

            // Update total stake
            s.stakedAmounts[_eventId] += msg.value;
        }

        if (_category == Types.PaidTicketCategory.REGULAR) {
            if (tickets.hasRegularTicket)
                revert("Regular tickets already created");
            if (tickets.hasVIPTicket && _ticketFee >= tickets.vipTicketFee) {
                revert Errors.RegularTicketMustCostLessThanVipTicket();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                _ticketFee,
                _ticketUri,
                "REGULAR"
            );

            tickets.hasRegularTicket = true;
            tickets.regularTicketFee = _ticketFee;
            tickets.regularTicketNFT = newTicketNFT;

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                _ticketFee,
                "REGULAR"
            );
        } else if (_category == Types.PaidTicketCategory.VIP) {
            if (tickets.hasVIPTicket) revert("VIP tickets already created");
            if (
                tickets.hasRegularTicket &&
                _ticketFee <= tickets.regularTicketFee
            ) {
                revert Errors.VipFeeTooLow();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                _ticketFee,
                _ticketUri,
                "VIP"
            );

            tickets.hasVIPTicket = true;
            tickets.vipTicketFee = _ticketFee;
            tickets.vipTicketNFT = newTicketNFT;

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                _ticketFee,
                "VIP"
            );
        }

        // If this wasn't the first ticket and additional value was sent, return it
        if (!firstTicket && msg.value > 0) {
            (bool success, ) = msg.sender.call{value: msg.value}("");
            require(success, "Failed to return excess value");
        }
    }

    /**
     * @dev Creates a new NFT ticket contract for an event
     * @param _eventId The ID of the event
     * @param _ticketFee The price of the ticket
     * @param _ticketUri The URI for the ticket metadata
     * @param _ticketType The type of ticket (FREE, REGULAR, or VIP)
     * @return Address of the newly created ticket NFT contract
     */
    function _createTicket(
        uint256 _eventId,
        uint256 _ticketFee,
        string memory _ticketUri,
        string memory _ticketType
    ) internal returns (address) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        Types.EventDetails storage eventDetails = s.events[_eventId];

        string memory ticketName = eventDetails.title;
        address newTicketNFT = address(
            new Ticket_NFT(address(this), _ticketUri, ticketName, _ticketType)
        );

        eventDetails.ticketNFTAddr = newTicketNFT;
        eventDetails.ticketFee = _ticketFee;
        s.organiserRevBal[eventDetails.organiser][_eventId] += 0;

        return newTicketNFT;
    }

    /**
     * @dev Enhanced attendance verification with proof
     * @param _eventId The ID of the event
     * @param _proof Cryptographic proof of attendance (can be expanded based on needs)
     */
    function verifyAttendanceWithProof(
        uint256 _eventId,
        bytes memory _proof
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Validate if event exist or has started
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (block.timestamp < eventDetails.startDate)
            revert Errors.EventNotStarted();

        // Check if attendee is registered
        if (!s.hasRegistered[msg.sender][_eventId])
            revert Errors.NotRegisteredForEvent();

        // Check if already verified
        if (s.isVerified[msg.sender][_eventId]) revert Errors.AlreadyVerified();

        // Validate proof
        require(_proof.length > 0, "Empty proof provided");

        // Store proof for future reference
        s.attendanceProofs[msg.sender][_eventId] = _proof;

        // Mark attendee as verified
        s.isVerified[msg.sender][_eventId] = true;
        eventDetails.verifiedAttendeesCount += 1;

        emit LibEvents.AttendeeVerified(_eventId, msg.sender, block.timestamp);
    }

    /**
     * @dev Returns all events a specific user has registered for
     * @param _user Address of the user to check
     * @return Array of event IDs the user has registered for
     */
    function allEventsRegisteredForByAUser(
        address _user
    ) external view returns (uint256[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (_user == address(0)) revert Errors.AddressZeroDetected();

        uint256 count = 0;

        // First pass: count events the user has registered for
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[_user][i]) {
                count++;
            }
        }

        // Second pass: populate the array
        uint256[] memory registeredEvents = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[_user][i]) {
                registeredEvents[index] = i;
                index++;
            }
        }

        return registeredEvents;
    }

    /**
     * @dev Determines if a user has a specific ticket type for an event
     * @param _user Address of the ticket holder to check
     * @param _eventId The ID of the event
     * @return ticketType String representation of ticket type ("FREE", "REGULAR", "VIP", or "NONE")
     */
    function getUserTicketType(
        address _user,
        uint256 _eventId
    ) public view returns (string memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (!s.hasRegistered[_user][_eventId]) {
            return "NONE";
        }

        Types.EventDetails storage eventDetails = s.events[_eventId];
        Types.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (eventDetails.ticketType == Types.TicketType.FREE) {
            return "FREE";
        }

        // Check for VIP ticket
        if (tickets.hasVIPTicket && tickets.vipTicketNFT != address(0)) {
            try ITicket_NFT(tickets.vipTicketNFT).balanceOf(_user) returns (
                uint256 balance
            ) {
                if (balance > 0) {
                    return "VIP";
                }
            } catch {}
        }

        // Check for REGULAR ticket
        if (
            tickets.hasRegularTicket && tickets.regularTicketNFT != address(0)
        ) {
            try ITicket_NFT(tickets.regularTicketNFT).balanceOf(_user) returns (
                uint256 balance
            ) {
                if (balance > 0) {
                    return "REGULAR";
                }
            } catch {}
        }

        return "UNKNOWN";
    }

    /**
     * @dev Helper to check if a user has a VIP ticket
     * @param _user Address of the ticket holder
     * @param _eventId The ID of the event
     * @return bool True if user has a VIP ticket
     */
    function hasVIPTicket(
        address _user,
        uint256 _eventId
    ) public view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (!tickets.hasVIPTicket || tickets.vipTicketNFT == address(0)) {
            return false;
        }

        try ITicket_NFT(tickets.vipTicketNFT).balanceOf(_user) returns (
            uint256 balance
        ) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev Returns all ticket details for a user across events
     * @return eventIds Array of event IDs the user has tickets for
     * @return ticketTypes Array of ticket types (FREE, REGULAR, VIP) corresponding to each event
     * @return verified Array indicating if attendance was verified for each event
     */
    function getMyTickets()
        external
        view
        returns (
            uint256[] memory eventIds,
            string[] memory ticketTypes,
            bool[] memory verified
        )
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        uint256 count = 0;

        // First pass: count tickets owned by the caller
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[msg.sender][i]) {
                count++;
            }
        }

        // Initialize return arrays
        eventIds = new uint256[](count);
        ticketTypes = new string[](count);
        verified = new bool[](count);
        uint256 index = 0;

        // Second pass: populate arrays with ticket details
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[msg.sender][i]) {
                eventIds[index] = i;
                verified[index] = s.isVerified[msg.sender][i];

                // Determine ticket type
                Types.TicketTypes storage tickets = s.eventTickets[i];

                if (s.events[i].ticketType == Types.TicketType.FREE) {
                    ticketTypes[index] = "FREE";
                } else {
                    // Check if user has VIP ticket
                    if (
                        tickets.hasVIPTicket &&
                        tickets.vipTicketNFT != address(0)
                    ) {
                        try
                            ITicket_NFT(tickets.vipTicketNFT).balanceOf(
                                msg.sender
                            )
                        returns (uint256 balance) {
                            if (balance > 0) {
                                ticketTypes[index] = "VIP";
                                index++;
                                continue;
                            }
                        } catch {}
                    }

                    // Check if user has REGULAR ticket
                    if (
                        tickets.hasRegularTicket &&
                        tickets.regularTicketNFT != address(0)
                    ) {
                        try
                            ITicket_NFT(tickets.regularTicketNFT).balanceOf(
                                msg.sender
                            )
                        returns (uint256 balance) {
                            if (balance > 0) {
                                ticketTypes[index] = "REGULAR";
                                index++;
                                continue;
                            }
                        } catch {}
                    }

                    // If we couldn't determine the exact type but user is registered
                    ticketTypes[index] = "UNKNOWN";
                }

                index++;
            }
        }

        return (eventIds, ticketTypes, verified);
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
            reputationDiscount =
                successEvents *
                LibConstants.REPUTATION_DISCOUNT_FACTOR;
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
     * @dev Validates event existence and organizer authorization
     * @param _eventId The ID of the event to validate
     */
    function _validateEventAndOrganizer(uint256 _eventId) internal view {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (msg.sender == address(0)) revert Errors.AddressZeroDetected();
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (msg.sender != s.events[_eventId].organiser)
            revert Errors.OnlyOrganiserCanCreateTicket();
    }
}
