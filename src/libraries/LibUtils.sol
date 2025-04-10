// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./LibAppStorage.sol";
import "./LibDiamond.sol";
import "./LibErrors.sol";
import "./LibTypes.sol";
import "./LibConstants.sol";
import "../interfaces/ITicketNFT.sol";

/**
 * @title LibUtils
 * @dev Library for common utility functions used across facets
 */
library LibUtils {
    /**
     * @dev function to restrict withdrawal function access to the contract owner
     */
    function onlyOwner() internal view {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        if (msg.sender != s.owner) revert LibErrors.OnlyOwnerAllowed();
    }

    /**
     * @dev Validates that an event exists and the caller is the organizer
     * @param _eventId The ID of the event to validate
     */
    function _validateEventAndOrganizer(uint256 _eventId) internal view {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }

        if (s.events[_eventId].organiser != msg.sender) {
            revert LibErrors.NotEventOrganizer();
        }
    }

    /**
     * @dev Checks if a user has a VIP ticket for an event
     * @param _user Address of the ticket holder
     * @param _eventId The ID of the event
     * @return bool True if user has a VIP ticket
     */
    function _hasVIPTicket(
        address _user,
        uint256 _eventId
    ) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (!tickets.hasVIPTicket || tickets.vipTicketNFT == address(0)) {
            return false;
        }

        try ITicketNFT(tickets.vipTicketNFT).balanceOf(_user) returns (
            uint256 balance
        ) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev Checks if a user has a regular ticket for an event
     * @param _user Address of the ticket holder
     * @param _eventId The ID of the event
     * @return bool True if user has a regular ticket
     */
    function _hasRegularTicket(
        address _user,
        uint256 _eventId
    ) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (
            !tickets.hasRegularTicket || tickets.regularTicketNFT == address(0)
        ) {
            return false;
        }

        try ITicketNFT(tickets.regularTicketNFT).balanceOf(_user) returns (
            uint256 balance
        ) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev Determines the type of ticket a user has for an event
     * @param _user Address of the ticket holder
     * @param _eventId The ID of the event
     * @return ticketType String representation of ticket type ("FREE", "REGULAR", "VIP", or "NONE")
     */
    function _getUserTicketType(
        address _user,
        uint256 _eventId
    ) internal view returns (string memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (!s.hasRegistered[_user][_eventId]) {
            return "NONE";
        }

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            return "FREE";
        }

        // Check for VIP ticket first
        if (_hasVIPTicket(_user, _eventId)) {
            return "VIP";
        }

        // Then check for REGULAR ticket
        if (_hasRegularTicket(_user, _eventId)) {
            return "REGULAR";
        }

        return "UNKNOWN";
    }

    /**
     * @dev Calculate required stake based on organizer reputation and event details
     * @param _organiser The address of the event organizer
     * @param _expectedAttendees Expected number of attendees
     * @param _ticketType Type of event (FREE or PAID)
     * @param _estimatedTicketFee Estimated ticket fee (0 for FREE events)
     * @return Required stake amount
     */
    function _calculateRequiredStake(
        address _organiser,
        uint256 _expectedAttendees,
        LibTypes.TicketType _ticketType,
        uint256 _estimatedTicketFee
    ) internal view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Blacklisted organizers cannot create events
        if (s.blacklistedOrganizers[_organiser]) {
            revert LibErrors.OrganizerIsBlacklisted();
        }

        // Free events have no stake requirement
        if (_ticketType == LibTypes.TicketType.FREE) {
            return 0;
        }

        // For paid events, calculate stake based on expected revenue
        uint256 expectedRevenue = _expectedAttendees * _estimatedTicketFee;
        uint256 baseStakePercentage = LibConstants.STAKE_PERCENTAGE;

        // Apply penalties for new organizers or those with scam history
        if (s.organizerSuccessfulEvents[_organiser] == 0) {
            baseStakePercentage += LibConstants.NEW_ORGANIZER_PENALTY;
        }

        // Add additional stake requirement for organizers with scam history
        if (s.organizerScammedEvents[_organiser] > 0) {
            baseStakePercentage += (s.organizerScammedEvents[_organiser] * 10); // +10% per scam event
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
}
