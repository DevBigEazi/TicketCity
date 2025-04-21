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
    LibAppStorage.AppStorage internal s;

    using LibTypes for *;
    using LibErrors for *;

    /**
     * @dev Allows a user to flag an event as invalid or scam
     * @param _eventId The ID of the event to flag
     * @param _reason Brief text explaining reason for flagging
     */
    function flagEvent(uint256 _eventId, string calldata _reason) external {
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

        // Check if user has already flagged
        if (s.hasFlaggedEvent[msg.sender][_eventId]) {
            revert LibErrors.AlreadyFlagged();
        }

        // Check reason length
        if (bytes(_reason).length > 32) {
            revert LibErrors.ReasonTooLong();
        }

        // Check if user is a ticket buyer
        if (s.hasRegistered[msg.sender][_eventId]) {
            // Determine flag weight based on ticket type (1 for standard, to be expanded later)
            uint256 weight = 1;

            // Mark as flagged and increment count with weight
            s.hasFlaggedEvent[msg.sender][_eventId] = true;
            s.flaggingWeight[msg.sender][_eventId] = weight;
            s.totalFlagsCount[_eventId] += weight;

            // Store reason in flag data
            LibTypes.FlagData storage newFlag = s.flagData[msg.sender][
                _eventId
            ];
            newFlag.evidence = _reason;
            newFlag.timestamp = block.timestamp;

            emit LibEvents.EventFlagged(
                _eventId,
                msg.sender,
                block.timestamp,
                weight
            );
        } else {
            revert LibErrors.NotRegisteredForEvent();
        }
    }

    /**
     * @dev Gets the flag threshold information for an event
     * @param _eventId The ID of the event
     * @return isFlagThresholdMet Whether the flag threshold has been met
     * @return flagCount Total count of flags
     * @return attendeeCount Total number of attendees
     * @return verifiedCount Number of verified attendees
     * @return nonVerifiedCount Number of non-verified attendees
     * @return requiredFlagCount Number of flags required to meet threshold
     */
    function getFlagThresholdInfo(
        uint256 _eventId
    )
        external
        view
        returns (
            bool isFlagThresholdMet,
            uint256 flagCount,
            uint256 attendeeCount,
            uint256 verifiedCount,
            uint256 nonVerifiedCount,
            uint256 requiredFlagCount
        )
    {
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Get basic counts
        attendeeCount = eventDetails.userRegCount;
        verifiedCount = eventDetails.verifiedAttendeesCount;
        flagCount = s.totalFlagsCount[_eventId];

        // If no attendees, no flags can be cast
        if (attendeeCount == 0) {
            return (false, 0, 0, 0, 0, 0);
        }

        // Calculate non-verified attendees
        nonVerifiedCount = attendeeCount > verifiedCount
            ? attendeeCount - verifiedCount
            : 0;

        // If everyone verified, no threshold can be met
        if (nonVerifiedCount == 0) {
            return (false, flagCount, attendeeCount, verifiedCount, 0, 0);
        }

        // Calculate required flags (70% of non-verified attendees)
        requiredFlagCount =
            (nonVerifiedCount * LibConstants.FLAGGING_THRESHOLD) /
            100;

        // Determine if threshold is met
        isFlagThresholdMet = flagCount >= requiredFlagCount;

        return (
            isFlagThresholdMet,
            flagCount,
            attendeeCount,
            verifiedCount,
            nonVerifiedCount,
            requiredFlagCount
        );
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

        // Check explanation length
        if (bytes(_explanation).length > 32) {
            revert LibErrors.ExplanationTooLong();
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
