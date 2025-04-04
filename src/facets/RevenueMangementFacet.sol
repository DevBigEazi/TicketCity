// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibTypes.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibUtils.sol";
import "../interfaces/ITicket_NFT.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RevenueManagementFacet
 * @dev Handles revenue management, release, refunds, and scam event processing
 */
contract RevenueManagementFacet is ReentrancyGuard {
    using LibTypes for *;
    using LibErrors for *;

    /**
     * @dev Releases event revenue to the organizer based on attendance rates and flagging status
     * @param _eventId The ID of the event
     */
    function releaseRevenue(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp <= eventDetails.endDate) {
            revert LibErrors.EventNotEnded();
        }

        // Check if revenue was already released
        if (s.revenueReleased[_eventId])
            revert LibErrors.RevenueAlreadyReleased();

        // Check if event was marked as scam
        if (s.eventConfirmedScam[_eventId])
            revert("Event confirmed as scam. Attendees should claim refunds");

        // Check if there's revenue to release
        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) revert LibErrors.NoRevenueToRelease();

        // Only event organizer can call this function
        if (msg.sender != eventDetails.organiser) {
            revert LibErrors.NotEventOrganizer();
        }

        // Calculate attendance rate
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if flagging period has ended (4 days after event end)
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;

        // Check if flagging threshold is met
        uint256 flagPercentage = 0;
        if (eventDetails.userRegCount > 0) {
            flagPercentage =
                (s.totalFlagsCount[_eventId] * 100) /
                eventDetails.userRegCount;
        }
        bool isFlaggingThresholdMet = flagPercentage >=
            LibConstants.FLAGGING_THRESHOLD;

        // If attendance rate is below minimum AND within flagging period, revert
        if (
            attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE &&
            !isAfterFlaggingPeriod
        ) {
            revert("Low attendance rate: Must wait 4 days after event ends");
        }

        // If flagging threshold is met, revert as event is flagged as scam
        if (isFlaggingThresholdMet) {
            revert(
                "Event has been flagged by attendees. Contact platform owner for review"
            );
        }

        // Mark revenue as released
        s.revenueReleased[_eventId] = true;

        // Transfer revenue to organizer
        s.organiserRevBal[eventDetails.organiser][_eventId] = 0;
        (bool success, ) = eventDetails.organiser.call{value: revenue}("");
        require(success, "Revenue transfer failed");

        // Update organizer reputation for successful event
        s.organizerSuccessfulEvents[eventDetails.organiser]++;

        // Emit event with appropriate details
        emit LibEvents.RevenueReleased(
            _eventId,
            eventDetails.organiser,
            revenue,
            attendanceRate,
            false
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

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp <= eventDetails.endDate) {
            revert LibErrors.EventNotEnded();
        }

        // Check if revenue was already released
        if (s.revenueReleased[_eventId])
            revert LibErrors.RevenueAlreadyReleased();

        // Check if event was confirmed as scam
        if (s.eventConfirmedScam[_eventId])
            revert("Event confirmed as scam, refunds in process");

        // Check if there's revenue to release
        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) revert LibErrors.NoRevenueToRelease();

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

        // Update organizer reputation for successful event
        s.organizerSuccessfulEvents[eventDetails.organiser]++;

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
     * @dev Allows contract owner to confirm an event as a scam
     * @param _eventId The ID of the event
     * @param _details Details about the scam investigation results
     */
    function confirmEventAsScam(
        uint256 _eventId,
        string calldata _details
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Only contract owner can do this
        require(
            msg.sender == s.owner,
            "Only contract owner can confirm event as scam"
        );

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }

        // Check time constraint - within 30 days of event end or manual review request
        uint256 reviewRequestTime = s.manualReviewRequestTime[_eventId];
        uint256 cutoffTime = reviewRequestTime > 0
            ? reviewRequestTime + LibConstants.SCAM_CONFIRM_PERIOD
            : eventDetails.endDate + LibConstants.SCAM_CONFIRM_PERIOD;

        require(
            block.timestamp <= cutoffTime,
            "Scam confirmation period has ended"
        );

        // Check if revenue was already released
        if (s.revenueReleased[_eventId])
            revert LibErrors.RevenueAlreadyReleased();

        // Check if already confirmed as scam
        if (s.eventConfirmedScam[_eventId])
            revert("Event already confirmed as scam");

        // Mark event as scam
        s.eventConfirmedScam[_eventId] = true;
        s.scamConfirmationDetails[_eventId] = _details;
        s.scamConfirmationTime[_eventId] = block.timestamp;

        // Penalize organizer by incrementing scam count
        s.organizerScammedEvents[eventDetails.organiser]++;

        // Add to platform revenue (10% of staked amount)
        uint256 stakedAmount = s.stakedAmounts[_eventId];
        if (stakedAmount > 0) {
            uint256 platformFee = (stakedAmount * 10) / 100; // 10% to platform
            s.platformRevenue += platformFee;
            s.stakedAmounts[_eventId] = stakedAmount - platformFee; // Reduce staked amount available for refunds
        }

        // Emit event for scam confirmation
        emit LibEvents.EventConfirmedAsScam(
            _eventId,
            block.timestamp,
            _details
        );
    }

    /**
     * @dev Allows a ticket buyer to claim refund for a confirmed scam event
     * @param _eventId The ID of the event
     */
    function claimScamEventRefund(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event is confirmed as scam
        require(s.eventConfirmedScam[_eventId], "Event not confirmed as scam");

        // Check if user is a ticket buyer
        require(
            s.hasRegistered[msg.sender][_eventId],
            "Not a ticket buyer for this event"
        );

        // Check if already claimed refund
        require(
            !s.hasClaimedRefund[msg.sender][_eventId],
            "Already claimed refund"
        );

        // Calculate basic refund (ticket price)
        uint256 refundAmount = 0;

        // Determine ticket type and price
        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            // Free events - no ticket price refund, only stake share
        } else {
            // Paid event - determine ticket type
            LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

            // Check if they have a VIP ticket
            if (LibUtils._hasVIPTicket(msg.sender, _eventId)) {
                refundAmount = tickets.vipTicketFee;
            } else if (LibUtils._hasRegularTicket(msg.sender, _eventId)) {
                refundAmount = tickets.regularTicketFee;
            }
        }

        // Add share of staked amount (90% divided among all attendees)
        uint256 stakeShare = 0;
        if (eventDetails.userRegCount > 0) {
            stakeShare =
                (s.stakedAmounts[_eventId] * 90) /
                (eventDetails.userRegCount * 100);
        }

        // Total refund = ticket price + stake share
        uint256 totalRefund = refundAmount + stakeShare;

        // Mark as claimed
        s.hasClaimedRefund[msg.sender][_eventId] = true;
        s.claimedRefundAmount[msg.sender][_eventId] = totalRefund;

        // Process refund from organizer revenue or staked amount
        uint256 revenueBalance = s.organiserRevBal[eventDetails.organiser][
            _eventId
        ];

        if (refundAmount <= revenueBalance) {
            // Refund ticket price from revenue
            s.organiserRevBal[eventDetails.organiser][_eventId] -= refundAmount;
        } else {
            // Not enough in revenue, take from remaining stake
            refundAmount = 0; // Cannot refund ticket price
        }

        // Send combined refund to buyer
        if (totalRefund > 0) {
            (bool success, ) = msg.sender.call{value: totalRefund}("");
            require(success, "Refund transfer failed");

            emit LibEvents.RefundClaimed(
                _eventId,
                msg.sender,
                totalRefund,
                stakeShare
            );
        }
    }

    /**
     * @dev Checks if an event can have its revenue released
     * @param _eventId The ID of the event to check
     * @return canRelease Whether revenue can be released
     * @return reason Reason code for status (0=can release, 1=waiting period, 2=flagged, 3=already released, 4=confirmed scam)
     */
    function checkReleaseStatus(
        uint256 _eventId
    ) external view returns (bool canRelease, uint8 reason) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

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

        // Check if confirmed as scam
        if (s.eventConfirmedScam[_eventId]) {
            return (false, 4); // Confirmed scam
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

        // Can release if after flagging period OR if attendance rate is sufficient
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;
        if (
            isAfterFlaggingPeriod ||
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
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        if (
            block.timestamp <= eventDetails.endDate ||
            s.revenueReleased[_eventId] ||
            s.eventConfirmedScam[_eventId]
        ) {
            return (false, 0, 0);
        }

        revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) {
            return (false, 0, 0);
        }

        attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if after flagging period or attendance rate meets requirement
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;
        canRelease =
            isAfterFlaggingPeriod ||
            attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE;

        return (canRelease, attendanceRate, revenue);
    }

    /**
     * @dev Function for contract owner to get a list of events that require manual validation
     * @return eventIds Array of event IDs needing manual review
     * @return organizers Array of organizer addresses corresponding to each event
     * @return attendanceRates Array of attendance rates for each event
     * @return flagPercentages Array of flag percentages for each event
     * @return revenues Array of revenue amounts for each event
     * @return hasRequestedReview Array indicating if organizer requested manual review
     */
    function getEventsRequiringManualReview()
        external
        view
        returns (
            uint256[] memory eventIds,
            address[] memory organizers,
            uint256[] memory attendanceRates,
            uint256[] memory flagPercentages,
            uint256[] memory revenues,
            bool[] memory hasRequestedReview
        )
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Count events requiring manual review
        uint256 count = 0;
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            LibTypes.EventDetails storage eventDetails = s.events[i];

            // Skip if already released, confirmed as scam, or event hasn't ended
            if (
                s.revenueReleased[i] ||
                s.eventConfirmedScam[i] ||
                block.timestamp <= eventDetails.endDate
            ) {
                continue;
            }

            uint256 revenue = s.organiserRevBal[eventDetails.organiser][i];
            if (revenue == 0) {
                continue;
            }

            uint256 attendanceRate = 0;
            if (eventDetails.userRegCount > 0) {
                attendanceRate =
                    (eventDetails.verifiedAttendeesCount * 100) /
                    eventDetails.userRegCount;
            }

            uint256 flagPercentage = 0;
            if (eventDetails.userRegCount > 0) {
                flagPercentage =
                    (s.totalFlagsCount[i] * 100) /
                    eventDetails.userRegCount;
            }

            // If attendance is low or event flagged, it needs review
            if (
                attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE ||
                flagPercentage >= LibConstants.FLAGGING_THRESHOLD
            ) {
                count++;
            }
        }

        // Initialize arrays
        eventIds = new uint256[](count);
        organizers = new address[](count);
        attendanceRates = new uint256[](count);
        flagPercentages = new uint256[](count);
        revenues = new uint256[](count);
        hasRequestedReview = new bool[](count);

        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            LibTypes.EventDetails storage eventDetails = s.events[i];

            // Skip if already released, confirmed as scam, or event hasn't ended
            if (
                s.revenueReleased[i] ||
                s.eventConfirmedScam[i] ||
                block.timestamp <= eventDetails.endDate
            ) {
                continue;
            }

            uint256 revenue = s.organiserRevBal[eventDetails.organiser][i];
            if (revenue == 0) {
                continue;
            }

            uint256 attendanceRate = 0;
            if (eventDetails.userRegCount > 0) {
                attendanceRate =
                    (eventDetails.verifiedAttendeesCount * 100) /
                    eventDetails.userRegCount;
            }

            uint256 flagPercentage = 0;
            if (eventDetails.userRegCount > 0) {
                flagPercentage =
                    (s.totalFlagsCount[i] * 100) /
                    eventDetails.userRegCount;
            }

            // If attendance is low or event flagged, add to arrays
            if (
                attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE ||
                flagPercentage >= LibConstants.FLAGGING_THRESHOLD
            ) {
                eventIds[index] = i;
                organizers[index] = eventDetails.organiser;
                attendanceRates[index] = attendanceRate;
                flagPercentages[index] = flagPercentage;
                revenues[index] = revenue;
                hasRequestedReview[index] = s.manualReviewRequestTime[i] > 0;
                index++;
            }
        }

        return (
            eventIds,
            organizers,
            attendanceRates,
            flagPercentages,
            revenues,
            hasRequestedReview
        );
    }

    /**
     * @dev Checks if a user can claim a refund for a scam event
     * @param _eventId The ID of the event
     * @param _user Address of the user to check
     * @return canClaim Whether the user can claim a refund
     * @return refundAmount Estimated refund amount (ticket price + stake share)
     * @return alreadyClaimed Whether user has already claimed
     */
    function checkRefundEligibility(
        uint256 _eventId,
        address _user
    )
        external
        view
        returns (bool canClaim, uint256 refundAmount, bool alreadyClaimed)
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event is confirmed as scam
        if (!s.eventConfirmedScam[_eventId]) {
            return (false, 0, false);
        }

        // Check if user is a ticket buyer
        if (!s.hasRegistered[_user][_eventId]) {
            return (false, 0, false);
        }

        // Check if already claimed
        if (s.hasClaimedRefund[_user][_eventId]) {
            return (false, s.claimedRefundAmount[_user][_eventId], true);
        }

        // Calculate ticket price refund
        uint256 ticketPrice = 0;
        if (eventDetails.ticketType != LibTypes.TicketType.FREE) {
            LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

            // Check if they have a VIP ticket
            if (LibUtils._hasVIPTicket(_user, _eventId)) {
                ticketPrice = tickets.vipTicketFee;
            } else if (LibUtils._hasRegularTicket(_user, _eventId)) {
                ticketPrice = tickets.regularTicketFee;
            }
        }

        // Calculate stake share (90% of stake divided by number of attendees)
        uint256 stakeShare = 0;
        if (eventDetails.userRegCount > 0) {
            stakeShare =
                (s.stakedAmounts[_eventId] * 90) /
                (eventDetails.userRegCount * 100);
        }

        return (true, ticketPrice + stakeShare, false);
    }
}
