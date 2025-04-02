// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ITicket_NFT.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RevenueManagementFacet
 * @dev Handles revenue management, release, and refunds
 */
contract RevenueManagementFacet is ReentrancyGuard {
    using Types for *;
    using Errors for *;

    /**
     * @dev Releases event revenue to the organizer based on attendance rates and flagging status
     * @param _eventId The ID of the event
     */
    function releaseRevenue(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (block.timestamp <= eventDetails.endDate)
            revert Errors.EventNotEnded();

        // Check if revenue was already released
        if (s.revenueReleased[_eventId]) revert Errors.RevenueAlreadyReleased();

        // Check if there's revenue to release
        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) revert Errors.NoRevenueToRelease();

        // Only event organizer can call this function
        if (msg.sender != eventDetails.organiser)
            revert Errors.NotEventOrganizer();

        // Calculate attendance rate
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if flagging period has ended (7 days after event end)
        bool isAfterWaitingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.WAITING_PERIOD;

        // Check if flagging threshold is met
        uint256 flagPercentage = 0;
        if (eventDetails.userRegCount > 0) {
            flagPercentage =
                (s.totalFlagsCount[_eventId] * 100) /
                eventDetails.userRegCount;
        }
        bool isFlaggingThresholdMet = flagPercentage >=
            LibConstants.FLAGGING_THRESHOLD;

        // If attendance rate is below minimum AND within waiting period, revert
        if (
            attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE &&
            !isAfterWaitingPeriod
        ) {
            revert("Low attendance rate: Must wait 7 days after event ends");
        }

        // If flagging threshold is met, revert as refunds should be processed instead
        if (isFlaggingThresholdMet) {
            revert(
                "Event has been flagged by attendees. Process refunds instead"
            );
        }

        // Mark revenue as released
        s.revenueReleased[_eventId] = true;

        // Transfer revenue to organizer
        s.organiserRevBal[eventDetails.organiser][_eventId] = 0;
        (bool success, ) = eventDetails.organiser.call{value: revenue}("");
        require(success, "Revenue transfer failed");

        // Refund damage fee if it was paid and event was successful
        if (
            s.damageFeesPaid[_eventId] > 0 &&
            attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE
        ) {
            uint256 damageFeeToBePaid = s.damageFeesPaid[_eventId];
            s.damageFeesPaid[_eventId] = 0;

            (bool feeRefundSuccess, ) = eventDetails.organiser.call{
                value: damageFeeToBePaid
            }("");
            if (feeRefundSuccess) {
                emit LibEvents.DamageFeeRefunded(
                    _eventId,
                    eventDetails.organiser,
                    damageFeeToBePaid
                );
            }
        }

        // Emit event with appropriate details
        emit LibEvents.RevenueReleased(
            _eventId,
            eventDetails.organiser,
            revenue,
            attendanceRate,
            isAfterWaitingPeriod
        );
    }

    /**
     * @dev Allows contract owner to manually release revenue for special cases
     * @param _eventId The ID of the event
     */
    function manualReleaseRevenue(uint256 _eventId) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        // Only contract owner can do this
        require(
            msg.sender == s.owner,
            "Only contract owner can manually release revenue"
        );

        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (block.timestamp <= eventDetails.endDate)
            revert Errors.EventNotEnded();

        // Check if revenue was already released
        if (s.revenueReleased[_eventId]) revert Errors.RevenueAlreadyReleased();

        // Check if there's revenue to release
        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) revert Errors.NoRevenueToRelease();

        // Calculate attendance rate for the event record
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Mark revenue as released
        s.revenueReleased[_eventId] = true;

        // Transfer revenue to organizer
        s.organiserRevBal[eventDetails.organiser][_eventId] = 0;
        (bool success, ) = eventDetails.organiser.call{value: revenue}("");
        require(success, "Revenue transfer failed");

        // Emit event showing this was manually released
        emit LibEvents.RevenueReleased(
            _eventId,
            eventDetails.organiser,
            revenue,
            attendanceRate,
            true
        );
    }

    /**
     * @dev Checks if an event can have its revenue released
     * @param _eventId The ID of the event to check
     * @return canRelease Whether revenue can be released
     * @return reason Reason code for status (0=can release, 1=waiting period, 2=flagged, 3=already released)
     */
    function checkReleaseStatus(
        uint256 _eventId
    ) external view returns (bool canRelease, uint8 reason) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (
            _eventId == 0 ||
            _eventId > s.totalEventOrganised ||
            block.timestamp <= eventDetails.endDate
        ) {
            return (false, 1); // Event doesn't exist or hasn't ended
        }

        // Check if revenue was already released
        if (s.revenueReleased[_eventId]) {
            return (false, 3); // Already released
        }

        // Calculate attendance rate
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if flagging threshold is met
        uint256 flagPercentage = 0;
        if (eventDetails.userRegCount > 0) {
            flagPercentage =
                (s.totalFlagsCount[_eventId] * 100) /
                eventDetails.userRegCount;
        }

        if (flagPercentage >= LibConstants.FLAGGING_THRESHOLD) {
            return (false, 2); // Flagged by users
        }

        // Can release if after waiting period OR if attendance rate is sufficient
        bool isAfterWaitingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.WAITING_PERIOD;
        if (
            isAfterWaitingPeriod ||
            attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE
        ) {
            return (true, 0); // Can release
        }

        return (false, 1); // Still in waiting period
    }

    /**
     * @dev Returns revenue details and determines if revenue can be automatically released
     * @param _eventId The ID of the event to check
     * @return canRelease Boolean indicating whether revenue can be released
     * @return attendanceRate The percentage of registered users who were verified as attendees
     * @return revenue The total revenue amount available for release
     */
    function canReleaseRevenue(
        uint256 _eventId
    )
        external
        view
        returns (bool canRelease, uint256 attendanceRate, uint256 revenue)
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        if (
            block.timestamp <= eventDetails.endDate ||
            s.revenueReleased[_eventId]
        ) {
            return (false, 0, 0);
        }

        revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) {
            return (false, 0, 0);
        }

        attendanceRate =
            (eventDetails.verifiedAttendeesCount * 100) /
            eventDetails.userRegCount;
        canRelease = attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE;

        return (canRelease, attendanceRate, revenue);
    }

    /**
     * @dev Process refunds for a flagged event
     * @param _eventId The ID of the event to process refunds for
     * @param _buyers Array of buyer addresses to refund
     */
    function processRefunds(
        uint256 _eventId,
        address[] calldata _buyers
    ) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Verify event and flagging status
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();

        // Get current flagging threshold based on time elapsed
        uint256 currentThreshold = getFlaggingThreshold(_eventId);

        // Check if flagging threshold is met
        uint256 flagPercentage = (s.totalFlagsCount[_eventId] * 100) /
            eventDetails.userRegCount;
        require(
            flagPercentage >= currentThreshold,
            "Flagging threshold not met"
        );

        // Only contract owner or event organizer can process refunds
        require(
            msg.sender == s.owner || msg.sender == eventDetails.organiser,
            "Only owner or organizer can process refunds"
        );

        // Check if revenue was already released
        require(!s.revenueReleased[_eventId], "Revenue already released");

        // Process refunds for each buyer
        for (uint256 i = 0; i < _buyers.length; i++) {
            address buyer = _buyers[i];

            // Verify buyer status
            if (!s.hasRegistered[buyer][_eventId]) continue;

            // Determine refund amount based on ticket type
            uint256 refundAmount = 0;
            Types.TicketTypes storage tickets = s.eventTickets[_eventId];

            if (eventDetails.ticketType == Types.TicketType.PAID) {
                // Check for VIP ticket
                if (hasVIPTicket(buyer, _eventId)) {
                    refundAmount = tickets.vipTicketFee;
                } else {
                    // Check for Regular ticket
                    try
                        ITicket_NFT(tickets.regularTicketNFT).balanceOf(buyer)
                    returns (uint256 balance) {
                        if (balance > 0) {
                            refundAmount = tickets.regularTicketFee;
                        }
                    } catch {}
                }
            }

            // Skip if no refund to process
            if (refundAmount == 0) continue;

            // Process refund from revenue or staked amount
            uint256 revenueBalance = s.organiserRevBal[eventDetails.organiser][
                _eventId
            ];

            if (refundAmount <= revenueBalance) {
                // Refund from revenue
                s.organiserRevBal[eventDetails.organiser][
                    _eventId
                ] -= refundAmount;
            } else {
                // If revenue isn't enough, use staked amount (for paid events)
                uint256 availableStake = s.stakedAmounts[_eventId];
                if (availableStake >= refundAmount) {
                    s.stakedAmounts[_eventId] -= refundAmount;
                } else {
                    // Not enough funds to refund fully
                    refundAmount = availableStake;
                    s.stakedAmounts[_eventId] = 0;
                }
            }

            // Send refund to buyer
            if (refundAmount > 0) {
                (bool success, ) = buyer.call{value: refundAmount}("");
                if (success) {
                    emit LibEvents.RefundProcessed(
                        _eventId,
                        buyer,
                        refundAmount
                    );
                }
            }
        }

        // Penalize organizer by incrementing scam count
        s.organizerScammedEvents[eventDetails.organiser]++;

        // Update reputation
        _adjustReputation(
            eventDetails.organiser,
            -int256(LibConstants.REPUTATION_CHANGE_BASE * 5)
        );
    }

    /**
     * @dev Return the current flagging threshold based on time elapsed since event end
     * @param _eventId The ID of the event
     * @return Current threshold percentage required for flagging
     */
    function getFlaggingThreshold(
        uint256 _eventId
    ) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Time since event ended
        uint256 timeElapsed = block.timestamp - eventDetails.endDate;

        // Require more flags as time passes (harder to scam flag)
        if (timeElapsed < 1 days) {
            return 70; // 70% threshold in first day
        } else if (timeElapsed < 3 days) {
            return 75; // 75% threshold between 1-3 days
        } else {
            return LibConstants.FLAGGING_THRESHOLD; // Default 80% after 3 days
        }
    }

    /**
     * @dev Adjust user reputation score within bounds
     * @param _user The address of the user
     * @param _change The change to apply (positive or negative)
     */
    function _adjustReputation(address _user, int256 _change) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        int256 currentScore = s.userReputationScores[_user];
        int256 newScore = currentScore + _change;

        // Ensure score stays within bounds
        if (newScore < LibConstants.MIN_REPUTATION_SCORE) {
            newScore = LibConstants.MIN_REPUTATION_SCORE;
        } else if (newScore > LibConstants.MAX_REPUTATION_SCORE) {
            newScore = LibConstants.MAX_REPUTATION_SCORE;
        }

        s.userReputationScores[_user] = newScore;

        emit LibEvents.ReputationChanged(_user, newScore, _change);
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
}
