// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibTypes.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FlaggingFacet
 * @dev Handles event flagging system with simplified approach
 */
contract FlaggingFacet is ReentrancyGuard {
    using LibTypes for *;
    using LibErrors for *;

    /**
     * @dev Allows a user to flag an event as invalid or scam
     * @param _eventId The ID of the event to flag
     * @param _reason Brief text explaining reason for flagging
     */
    function flagEvent(uint256 _eventId, string calldata _reason) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp <= eventDetails.endDate) {
            revert LibErrors.EventNotEnded();
        }

        // Check if flagging period has ended
        if (
            block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD
        ) {
            revert LibErrors.FlaggingPeriodEnded();
        }

        // Check if user is a ticket buyer
        if (!s.hasRegistered[msg.sender][_eventId]) {
            revert LibErrors.NotRegisteredForEvent();
        }

        // Check if user has already flagged
        if (s.hasFlaggedEvent[msg.sender][_eventId]) {
            revert LibErrors.AlreadyFlagged();
        }

        // Determine flag weight based on ticket type (1 for standard, to be expanded later)
        uint256 weight = 1; 

        // Mark as flagged and increment count with weight
        s.hasFlaggedEvent[msg.sender][_eventId] = true;
        s.flaggingWeight[msg.sender][_eventId] = weight;
        s.totalFlagsCount[_eventId] += weight;

        // Store reason in flag data
        LibTypes.FlagData storage newFlag = s.flagData[msg.sender][_eventId];
        newFlag.evidence = _reason;
        newFlag.timestamp = block.timestamp;

        emit LibEvents.EventFlagged(
            _eventId,
            msg.sender,
            block.timestamp,
            weight
        );
    }

    /**
     * @dev Gets the percentage of attendees who have flagged the event
     * @param _eventId The ID of the event
     * @return flagPercentage Percentage of attendees who flagged the event
     * @return flagCount Total count of flags
     * @return attendeeCount Total number of attendees
     */
    function getFlagPercentage(
        uint256 _eventId
    )
        external
        view
        returns (
            uint256 flagPercentage,
            uint256 flagCount,
            uint256 attendeeCount
        )
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        if (eventDetails.userRegCount == 0) {
            return (0, 0, 0);
        }

        flagCount = s.totalFlagsCount[_eventId];
        attendeeCount = eventDetails.userRegCount;
        flagPercentage = (flagCount * 100) / attendeeCount;

        return (flagPercentage, flagCount, attendeeCount);
    }

    /**
     * @dev Allows organizer to request manual review with explanation
     * @param _eventId The ID of the event
     * @param _explanation Explanation for the review request
     */
    function requestManualReview(
        uint256 _eventId,
        string calldata _explanation
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if caller is the organizer
        if (msg.sender != eventDetails.organiser) {
            revert LibErrors.NotEventOrganizer();
        }

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp <= eventDetails.endDate) {
            revert LibErrors.EventNotEnded();
        }

        // Check if revenue was already released
        if (s.revenueReleased[_eventId]) {
            revert LibErrors.RevenueAlreadyReleased();
        }

        // Check if there's revenue to release
        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) {
            revert LibErrors.NoRevenueToRelease();
        }

        // Store explanation
        s.disputeEvidence[_eventId] = _explanation;

        // Mark as requiring manual review
        s.eventDisputed[_eventId] = true;

        emit LibEvents.ManualReviewRequested(
            _eventId,
            msg.sender,
            _explanation
        );
    }
}
